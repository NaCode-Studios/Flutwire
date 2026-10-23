import 'package:flutter/foundation.dart';

import '../../model/call.dart';

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
  /// Creates a controller that follows [source].
  InspectorController(this.source) {
    source.addListener(_sourceChanged);
  }

  /// The whole history, newest first.
  final ValueListenable<List<FlutwireCall>> source;

  String _query = '';
  final Set<String> _methods = {};
  final Set<StateFilter> _states = {};
  InspectorSort _sort = InspectorSort.newest;
  final Set<int> _selection = {};
  List<FlutwireCall>? _visible;
  bool _disposed = false;

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
    _changed();
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
        if (_matchesQuery(call, q, digits) &&
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
