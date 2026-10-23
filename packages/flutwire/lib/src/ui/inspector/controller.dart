import 'package:flutter/foundation.dart';

import '../../model/call.dart';

/// Reads a call back with its bodies, which a history kept on disk does not
/// hold in memory.
typedef CallLoader = Future<FlutwireCall?> Function(int id);

/// How the list is ordered.
enum InspectorSort {
  /// The newest call first.
  newest,

  /// The slowest call first.
  slowest,

  /// The call that moved the most bytes first.
  largest,
}

/// A narrowing of the list by how a call went.
enum StateFilter {
  /// 2xx.
  success,

  /// 3xx.
  redirect,

  /// 4xx.
  clientError,

  /// 5xx.
  serverError,

  /// No response.
  failed,

  /// Still running.
  running,

  /// Pinned by the user.
  pinned,
}

/// The methods the filter names; every other method counts as [other].
const List<String> filterMethods = ['GET', 'POST', 'PUT', 'PATCH', 'DELETE'];

/// The key of every method the filter does not name.
const String other = 'OTHER';

/// What the list shows, and what the user did to narrow and order it.
///
/// The controller follows the history it is given and keeps the narrowed list
/// ready, so a screen only has to rebuild when something changes.
class InspectorController extends ChangeNotifier {
  /// Creates a controller that follows [source]. With a [loadCall], the search
  /// also looks inside request and response bodies.
  InspectorController(this.source, {this.loadCall}) {
    source.addListener(_sourceChanged);
  }

  /// The whole history, newest first.
  final ValueListenable<List<FlutwireCall>> source;

  /// How a call is read back with its bodies, or null to search without them.
  final CallLoader? loadCall;

  String _query = '';
  final Set<String> _methods = {};
  final Set<StateFilter> _states = {};
  InspectorSort _sort = InspectorSort.newest;
  final Set<int> _selection = {};
  List<FlutwireCall>? _visible;
  bool _disposed = false;

  // The body search runs beside the list: calls whose bodies hold the text are
  // added to it as they are found, so a long history never blocks the screen.
  final Set<int> _bodyMatches = {};
  final Set<int> _scanned = {};
  int _searchToken = 0;
  bool _scanning = false;

  /// The text typed in the search field.
  String get query => _query;

  /// The methods the list is narrowed to, or none for all of them.
  Set<String> get methods => Set.unmodifiable(_methods);

  /// The states the list is narrowed to, or none for all of them.
  Set<StateFilter> get states => Set.unmodifiable(_states);

  /// The current order.
  InspectorSort get sort => _sort;

  /// The ids of the selected calls.
  Set<int> get selection => Set.unmodifiable(_selection);

  /// Whether a selection is in progress.
  bool get isSelecting => _selection.isNotEmpty;

  /// Whether the bodies are still being read for the text in the search field.
  bool get isSearchingBodies => _scanning;

  /// Whether anything narrows the list.
  bool get hasFilters =>
      _query.trim().isNotEmpty || _methods.isNotEmpty || _states.isNotEmpty;

  /// Every call, before any narrowing.
  List<FlutwireCall> get all => source.value;

  /// The calls that pass the search and the filters, in the chosen order.
  List<FlutwireCall> get visible => _visible ??= _compute();

  /// Sets the search text.
  void setQuery(String value) {
    if (value == _query) return;
    _query = value;
    _restartBodySearch();
    _changed();
  }

  /// Turns the filter for [method] on or off. Use [other] for the rest.
  void toggleMethod(String method) {
    if (!_methods.remove(method)) _methods.add(method);
    _changed();
  }

  /// Turns [state] on or off.
  void toggleState(StateFilter state) {
    if (!_states.remove(state)) _states.add(state);
    _changed();
  }

  /// Chooses the order.
  void setSort(InspectorSort value) {
    if (value == _sort) return;
    _sort = value;
    _changed();
  }

  /// Removes the search and every filter.
  void clearFilters() {
    _query = '';
    _restartBodySearch();
    _methods.clear();
    _states.clear();
    _changed();
  }

  /// Adds or removes a call from the selection.
  void toggleSelected(int id) {
    if (!_selection.remove(id)) _selection.add(id);
    notifyListeners();
  }

  /// Selects everything that is visible.
  void selectAllVisible() {
    _selection
      ..clear()
      ..addAll(visible.map((c) => c.id));
    notifyListeners();
  }

  /// Ends the selection.
  void clearSelection() {
    if (_selection.isEmpty) return;
    _selection.clear();
    notifyListeners();
  }

  /// The selected calls that still exist, newest first.
  List<FlutwireCall> get selectedCalls => [
    for (final c in all)
      if (_selection.contains(c.id)) c,
  ];

  void _sourceChanged() {
    // A call that is gone cannot stay selected.
    final ids = {for (final c in all) c.id};
    _selection.removeWhere((id) => !ids.contains(id));
    _bodyMatches.removeWhere((id) => !ids.contains(id));
    _scanned.removeWhere((id) => !ids.contains(id));
    // Calls that arrived or finished since the last pass still have to be read.
    _scanBodies(_searchToken);
    _changed();
  }

  /// The text a body search looks for, or null when the query is not one: a
  /// few digits are a status code, and one character matches nearly anything.
  String? get _bodyQuery {
    final q = _query.trim().toLowerCase();
    if (loadCall == null || q.length < 2) return null;
    if (q.length <= 3 && int.tryParse(q) != null) return null;
    return q;
  }

  void _restartBodySearch() {
    _searchToken++;
    _bodyMatches.clear();
    _scanned.clear();
    _scanning = false;
    _scanBodies(_searchToken);
  }

  Future<void> _scanBodies(int token) async {
    final load = loadCall;
    final q = _bodyQuery;
    if (load == null || q == null || _scanning || _disposed) return;
    _scanning = true;
    notifyListeners();
    var read = 0;
    try {
      while (token == _searchToken && !_disposed) {
        final next = [
          for (final c in all)
            if (!c.isPending &&
                !_scanned.contains(c.id) &&
                !c.searchText.contains(q))
              c.id,
        ];
        if (next.isEmpty) break;
        for (final id in next) {
          if (token != _searchToken || _disposed) return;
          _scanned.add(id);
          final full = await load(id);
          if (full != null && _bodyHolds(full, q) && token == _searchToken) {
            _bodyMatches.add(id);
            _changed();
          }
          // Let the screen draw between batches of reads.
          if (++read % 6 == 0) await Future<void>.delayed(Duration.zero);
        }
      }
    } finally {
      if (token == _searchToken) {
        _scanning = false;
        if (!_disposed) notifyListeners();
      }
    }
  }

  static bool _bodyHolds(FlutwireCall call, String q) {
    final request = call.request.body.text;
    if (request != null && request.toLowerCase().contains(q)) return true;
    final response = call.response?.body.text;
    return response != null && response.toLowerCase().contains(q);
  }

  void _changed() {
    if (_disposed) return;
    _visible = null;
    notifyListeners();
  }

  List<FlutwireCall> _compute() {
    final q = _query.trim().toLowerCase();
    final digits = q.isNotEmpty && q.length <= 3 && int.tryParse(q) != null;
    final out = <FlutwireCall>[
      for (final call in all)
        if ((_matchesQuery(call, q, digits) ||
                _bodyMatches.contains(call.id)) &&
            _matchesMethod(call) &&
            _matchesState(call))
          call,
    ];
    switch (_sort) {
      case InspectorSort.newest:
        break;
      case InspectorSort.slowest:
        out.sort((a, b) => b.duration.compareTo(a.duration));
      case InspectorSort.largest:
        out.sort(
          (a, b) => (b.requestSize + b.responseSize).compareTo(
            a.requestSize + a.responseSize,
          ),
        );
    }
    return out;
  }

  static bool _matchesQuery(FlutwireCall call, String q, bool digits) {
    if (q.isEmpty) return true;
    // A few digits are a status code, so "40" finds 400 and 404 and not every
    // URL with a 40 in it.
    if (digits) return '${call.statusCode ?? ''}'.startsWith(q);
    return call.searchText.contains(q);
  }

  bool _matchesMethod(FlutwireCall call) {
    if (_methods.isEmpty) return true;
    final key = filterMethods.contains(call.method) ? call.method : other;
    return _methods.contains(key);
  }

  bool _matchesState(FlutwireCall call) {
    if (_states.isEmpty) return true;
    for (final state in _states) {
      final hit = switch (state) {
        StateFilter.success => call.statusClass == FlutwireStatusClass.success,
        StateFilter.redirect =>
          call.statusClass == FlutwireStatusClass.redirect,
        StateFilter.clientError =>
          call.statusClass == FlutwireStatusClass.clientError,
        StateFilter.serverError =>
          call.statusClass == FlutwireStatusClass.serverError,
        StateFilter.failed => call.state == FlutwireCallState.failed,
        StateFilter.running => call.isPending,
        StateFilter.pinned => call.pinned,
      };
      if (hit) return true;
    }
    return false;
  }

  @override
  void dispose() {
    _disposed = true;
    source.removeListener(_sourceChanged);
    super.dispose();
  }
}
