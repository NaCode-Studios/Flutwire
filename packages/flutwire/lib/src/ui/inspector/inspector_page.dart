import 'dart:async';

import 'package:flutter/material.dart';

import '../../model/call.dart';
import '../../session.dart';
import '../detail/call_detail_page.dart';
import '../scope.dart';
import '../shell.dart';
import '../theme/tokens.dart';
import '../widgets/call_tile.dart';
import '../widgets/empty_state.dart';
import '../widgets/metric_strip.dart';
import 'app_bars.dart';
import 'controller.dart';
import 'filter_bar.dart';
import 'pinned_bar.dart';
import 'recording_row.dart';

/// The inspector: the history as a list, with search, filters, order and a
/// selection. On a wide screen the call that is open sits beside the list.
class InspectorPage extends StatefulWidget {
  /// Creates the inspector.
  const InspectorPage({super.key});

  @override
  State<InspectorPage> createState() => _InspectorPageState();
}

class _InspectorPageState extends State<InspectorPage> {
  /// The width from which the open call sits beside the list.
  static const double _wideFrom = 880;

  /// How wide the list is when the call sits beside it.
  static const double _listWidth = 420;

  late final FlutwireSession _session;
  late final InspectorController _controller;
  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final ScrollController _scroll = ScrollController();
  Timer? _clock;
  Timer? _debounce;
  bool _searching = false;
  int? _openId;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _session = context.session;
    _controller = InspectorController(
      _session.store.calls,
      loadCall: _session.store.load,
    );
    // Relative times ("12s", "4m") move on by themselves.
    _clock = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _debounce?.cancel();
    _controller.dispose();
    _search.dispose();
    _searchFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() => _searching = !_searching);
    if (_searching) {
      // The field sits at the top of the list.
      if (_scroll.hasClients && _scroll.offset > 0) {
        unawaited(
          _scroll.animateTo(
            0,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          ),
        );
      }
      _searchFocus.requestFocus();
    } else {
      _search.clear();
      _controller.setQuery('');
    }
  }

  void _searchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 120),
      () => _controller.setQuery(value),
    );
  }

  void _openCall(FlutwireCall call, {required bool wide}) {
    if (wide) {
      setState(() => _openId = call.id);
      return;
    }
    unawaited(
      Navigator.of(context).push(
        shellRoute(
          _session,
          name: 'flutwire/call',
          child: CallDetailPage(callId: call.id),
        ),
      ),
    );
  }

  Future<void> _confirmClear() async {
    final s = context.strings;
    final ok = await _confirm(
      title: s.clearHistoryTitle,
      message: s.clearHistoryBody(_controller.all.length),
      action: s.clearHistory,
    );
    if (ok != true) return;
    _controller.clearSelection();
    await _session.clear();
  }

  Future<void> _confirmDeleteSelected() async {
    final s = context.strings;
    final ok = await _confirm(
      title: s.deleteSelectedTitle,
      message: s.selected(_controller.selection.length),
      action: s.delete,
    );
    if (ok != true) return;
    final ids = _controller.selection.toList();
    _controller.clearSelection();
    await _session.store.remove(ids);
  }

  Future<bool?> _confirm({
    required String title,
    required String message,
    required String action,
  }) {
    final s = context.strings;
    final t = context.fw;
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action, style: TextStyle(color: t.error)),
          ),
        ],
      ),
    );
  }

  Future<void> _togglePinSelected() async {
    final calls = _controller.selectedCalls;
    final pin = calls.any((c) => !c.pinned);
    await _session.store.setPinned(calls.map((c) => c.id), pinned: pin);
    _controller.clearSelection();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => LayoutBuilder(
        builder: (context, box) {
          final wide = box.maxWidth >= _wideFrom;
          final list = _buildListPane(context, wide: wide);
          if (!wide) return list;
          final t = context.fw;
          return Scaffold(
            body: Row(
              children: [
                SizedBox(width: _listWidth, child: list),
                VerticalDivider(width: 1, color: t.line),
                Expanded(
                  child: _openId == null
                      ? Center(
                          child: Text(
                            context.strings.pickACall,
                            style: t.body(color: t.faint),
                          ),
                        )
                      : CallDetailPage(
                          key: ValueKey(_openId),
                          callId: _openId!,
                          embedded: true,
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildListPane(BuildContext context, {required bool wide}) {
    final t = context.fw;
    final s = context.strings;
    final visible = _controller.visible;
    final selecting = _controller.isSelecting;
    return Scaffold(
      appBar: selecting
          ? SelectionAppBar(
              controller: _controller,
              onTogglePin: () => unawaited(_togglePinSelected()),
              onDelete: () => unawaited(_confirmDeleteSelected()),
            )
          : InspectorAppBar(
              controller: _controller,
              wide: wide,
              searching: _searching,
              onToggleSearch: _toggleSearch,
              onClearHistory: () => unawaited(_confirmClear()),
            ),
      // The recording row and the numbers scroll away with the list, so a phone
      // keeps its height for the calls. The filters stay.
      body: CustomScrollView(
        controller: _scroll,
        slivers: [
          SliverToBoxAdapter(
            child: RecordingRow(
              sort: _controller.sort,
              onSort: _controller.setSort,
            ),
          ),
          SliverToBoxAdapter(child: MetricStrip(calls: visible)),
          SliverToBoxAdapter(
            child: AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              child: _searching
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: TextField(
                        controller: _search,
                        focusNode: _searchFocus,
                        textInputAction: TextInputAction.search,
                        onChanged: _searchChanged,
                        style: t.mono(size: 13, color: t.ink),
                        decoration: InputDecoration(
                          hintText: s.searchHint,
                          prefixIcon: Icon(
                            Icons.search_rounded,
                            color: t.faint,
                          ),
                          suffixIcon: IconButton(
                            tooltip: s.close,
                            icon: const Icon(Icons.close_rounded),
                            onPressed: _toggleSearch,
                          ),
                        ),
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: PinnedBar(
              height: FilterBar.height + 2,
              builder: (context, overlaps) => DecoratedBox(
                decoration: BoxDecoration(
                  color: t.ground,
                  border: Border(
                    bottom: BorderSide(
                      color: overlaps ? t.line : Colors.transparent,
                    ),
                  ),
                ),
                child: Column(
                  children: [
                    SizedBox(
                      height: 2,
                      child: _controller.isSearchingBodies
                          ? LinearProgressIndicator(
                              minHeight: 2,
                              color: FlutwireTokens.copper,
                              backgroundColor: t.line,
                            )
                          : null,
                    ),
                    FilterBar(controller: _controller),
                  ],
                ),
              ),
            ),
          ),
          if (visible.isEmpty)
            SliverFillRemaining(hasScrollBody: false, child: _emptyState())
          else
            SliverList.builder(
              itemCount: visible.length,
              itemBuilder: (context, index) {
                final call = visible[index];
                return CallTile(
                  key: ValueKey(call.id),
                  call: call,
                  now: _now,
                  selecting: selecting,
                  selected:
                      _controller.selection.contains(call.id) ||
                      (wide && _openId == call.id && !selecting),
                  onTap: () => selecting
                      ? _controller.toggleSelected(call.id)
                      : _openCall(call, wide: wide),
                  onLongPress: () => _controller.toggleSelected(call.id),
                );
              },
            ),
          // The last call must be able to scroll clear of the gesture bar.
          SliverToBoxAdapter(
            child: SizedBox(height: MediaQuery.paddingOf(context).bottom + 12),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    final s = context.strings;
    if (_controller.isSearchingBodies) {
      return EmptyState(title: s.searchingBodies);
    }
    if (_controller.hasFilters) {
      return EmptyState(
        title: s.emptyFiltered,
        actionLabel: s.clearFilters,
        action: () {
          _search.clear();
          _controller.clearFilters();
        },
      );
    }
    return EmptyState(title: s.emptyTitle, message: s.emptyBody);
  }
}
