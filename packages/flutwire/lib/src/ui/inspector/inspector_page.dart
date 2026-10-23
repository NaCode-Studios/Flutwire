import 'dart:async';

import 'package:flutter/material.dart';

import '../../export/export.dart';
import '../../flutwire.dart';
import '../../model/call.dart';
import '../actions.dart';
import '../detail/call_detail_page.dart';
import '../scope.dart';
import '../settings/settings_sheet.dart';
import '../shell.dart';
import '../theme/tokens.dart';
import '../widgets/call_tile.dart';
import '../widgets/chip.dart';
import '../widgets/empty_state.dart';
import '../widgets/mark.dart';
import '../widgets/metric_strip.dart';
import '../widgets/pulse.dart';
import '../widgets/wire_rule.dart';
import 'controller.dart';

/// The inspector: the history as a list, with search, filters, order and a
/// selection. On a wide screen the call that is open sits beside the list.
class InspectorPage extends StatefulWidget {
  /// Creates the inspector.
  const InspectorPage({super.key});

  @override
  State<InspectorPage> createState() => _InspectorPageState();
}

class _InspectorPageState extends State<InspectorPage> {
  late final InspectorController _controller = InspectorController(
    Flutwire.calls,
  );
  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  Timer? _clock;
  Timer? _debounce;
  bool _searching = false;
  int? _openId;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
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
    super.dispose();
  }

  void _toggleSearch() {
    setState(() => _searching = !_searching);
    if (_searching) {
      _searchFocus.requestFocus();
    } else {
      _search.clear();
      _controller.setQuery('');
    }
  }

  void _openCall(FlutwireCall call, {required bool wide}) {
    if (wide) {
      setState(() => _openId = call.id);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'flutwire/call'),
        builder: (_) => FlutwireShell(child: CallDetailPage(callId: call.id)),
      ),
    );
  }

  Future<void> _confirmClear() async {
    final s = context.strings;
    final count = _controller.all.length;
    final ok = await _confirm(
      title: s.clearHistoryTitle,
      message: s.clearHistoryBody(count),
      action: s.clearHistory,
    );
    if (ok == true) {
      _controller.clearSelection();
      await Flutwire.clear();
    }
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
    await Flutwire.store?.remove(ids);
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
    await Flutwire.store?.setPinned(calls.map((c) => c.id), pinned: pin);
    _controller.clearSelection();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_controller, Flutwire.pausedListenable]),
      builder: (context, _) => LayoutBuilder(
        builder: (context, box) {
          final wide = box.maxWidth >= 880;
          final list = _buildListPane(context, wide: wide);
          if (!wide) return list;
          final t = context.fw;
          return Scaffold(
            body: Row(
              children: [
                SizedBox(width: 420, child: list),
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
      appBar: selecting ? _selectionBar(context) : _normalBar(context, wide),
      body: Column(
        children: [
          _RecordingRow(sort: _controller.sort, onSort: _controller.setSort),
          MetricStrip(calls: visible),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            child: _searching
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: TextField(
                      controller: _search,
                      focusNode: _searchFocus,
                      textInputAction: TextInputAction.search,
                      onChanged: (value) {
                        _debounce?.cancel();
                        _debounce = Timer(
                          const Duration(milliseconds: 120),
                          () => _controller.setQuery(value),
                        );
                      },
                      style: t.mono(size: 13, color: t.ink),
                      decoration: InputDecoration(
                        hintText: s.searchHint,
                        prefixIcon: Icon(Icons.search_rounded, color: t.faint),
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
          _FilterBar(controller: _controller),
          Expanded(
            child: visible.isEmpty
                ? (_controller.hasFilters
                      ? EmptyState(
                          title: s.emptyFiltered,
                          actionLabel: s.clearFilters,
                          action: () {
                            _search.clear();
                            _controller.clearFilters();
                          },
                        )
                      : EmptyState(title: s.emptyTitle, message: s.emptyBody))
                : ListView.builder(
                    itemCount: visible.length,
                    itemExtent: null,
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
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _normalBar(BuildContext context, bool wide) {
    final t = context.fw;
    final s = context.strings;
    return AppBar(
      automaticallyImplyLeading: !wide,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const FlutwireMark(size: 20),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              s.inspectorTitle,
              style: t.display(size: 20),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      bottom: const PreferredSize(
        preferredSize: Size.fromHeight(WireRule.height),
        child: WireRule(),
      ),
      actions: [
        IconButton(
          tooltip: s.search,
          icon: Icon(
            _searching ? Icons.search_off_rounded : Icons.search_rounded,
          ),
          onPressed: _toggleSearch,
        ),
        PopupMenuButton<_Menu>(
          tooltip: '',
          icon: const Icon(Icons.more_vert_rounded),
          onSelected: (value) async {
            switch (value) {
              case _Menu.pause:
                Flutwire.isPaused = !Flutwire.isPaused;
              case _Menu.exportText:
                await shareCalls(
                  context,
                  _controller.all,
                  FlutwireExportFormat.text,
                );
              case _Menu.exportCurl:
                await shareCalls(
                  context,
                  _controller.all,
                  FlutwireExportFormat.curl,
                );
              case _Menu.exportHar:
                await shareCalls(
                  context,
                  _controller.all,
                  FlutwireExportFormat.har,
                );
              case _Menu.exportJson:
                await shareCalls(
                  context,
                  _controller.all,
                  FlutwireExportFormat.json,
                );
              case _Menu.settings:
                await showSettingsSheet(context);
              case _Menu.clear:
                await _confirmClear();
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: _Menu.pause,
              child: Text(
                Flutwire.isPaused ? s.resumeRecording : s.pauseRecording,
              ),
            ),
            const PopupMenuDivider(),
            PopupMenuItem(
              value: _Menu.exportText,
              child: Text('${s.exportAll}: ${FlutwireExportFormat.text.label}'),
            ),
            PopupMenuItem(
              value: _Menu.exportCurl,
              child: Text('${s.exportAll}: ${FlutwireExportFormat.curl.label}'),
            ),
            PopupMenuItem(
              value: _Menu.exportHar,
              child: Text('${s.exportAll}: ${FlutwireExportFormat.har.label}'),
            ),
            PopupMenuItem(
              value: _Menu.exportJson,
              child: Text('${s.exportAll}: ${FlutwireExportFormat.json.label}'),
            ),
            const PopupMenuDivider(),
            PopupMenuItem(value: _Menu.settings, child: Text(s.settings)),
            PopupMenuItem(
              value: _Menu.clear,
              child: Text(s.clearHistory, style: TextStyle(color: t.error)),
            ),
          ],
        ),
      ],
    );
  }

  PreferredSizeWidget _selectionBar(BuildContext context) {
    final t = context.fw;
    final s = context.strings;
    return AppBar(
      backgroundColor: t.raised,
      leading: IconButton(
        tooltip: s.close,
        icon: const Icon(Icons.close_rounded),
        onPressed: _controller.clearSelection,
      ),
      title: Text(
        s.selected(_controller.selection.length),
        style: t.display(size: 18),
      ),
      actions: [
        IconButton(
          tooltip: s.selectAll,
          icon: const Icon(Icons.select_all_rounded),
          onPressed: _controller.selectAllVisible,
        ),
        IconButton(
          tooltip: s.pin,
          icon: const Icon(Icons.push_pin_outlined),
          onPressed: _togglePinSelected,
        ),
        Builder(
          builder: (context) => IconButton(
            tooltip: s.share,
            icon: const Icon(Icons.ios_share_rounded),
            onPressed: () => shareCalls(
              context,
              _controller.selectedCalls,
              FlutwireExportFormat.text,
            ),
          ),
        ),
        IconButton(
          tooltip: s.delete,
          icon: Icon(Icons.delete_outline_rounded, color: t.error),
          onPressed: _confirmDeleteSelected,
        ),
      ],
    );
  }
}

enum _Menu {
  pause,
  exportText,
  exportCurl,
  exportHar,
  exportJson,
  settings,
  clear,
}

class _RecordingRow extends StatelessWidget {
  const _RecordingRow({required this.sort, required this.onSort});

  final InspectorSort sort;
  final ValueChanged<InspectorSort> onSort;

  @override
  Widget build(BuildContext context) {
    final t = context.fw;
    final s = context.strings;
    final paused = Flutwire.isPaused;
    final dot = paused ? t.warning : FlutwireTokens.copper;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
      child: Row(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Flutwire.isPaused = !paused,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Pulse(
                  active: !paused,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: dot,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: dot.withValues(alpha: 0.5),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  (paused ? s.paused : s.recording).toUpperCase(),
                  style: t.label(color: paused ? t.warning : t.muted),
                ),
              ],
            ),
          ),
          const Spacer(),
          PopupMenuButton<InspectorSort>(
            tooltip: s.sortBy,
            initialValue: sort,
            onSelected: onSort,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(switch (sort) {
                    InspectorSort.newest => s.sortNewest,
                    InspectorSort.slowest => s.sortSlowest,
                    InspectorSort.largest => s.sortLargest,
                  }, style: t.body(size: 12, color: t.muted)),
                  const SizedBox(width: 2),
                  Icon(Icons.expand_more_rounded, size: 18, color: t.muted),
                ],
              ),
            ),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: InspectorSort.newest,
                child: Text(s.sortNewest),
              ),
              PopupMenuItem(
                value: InspectorSort.slowest,
                child: Text(s.sortSlowest),
              ),
              PopupMenuItem(
                value: InspectorSort.largest,
                child: Text(s.sortLargest),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.controller});

  final InspectorController controller;

  @override
  Widget build(BuildContext context) {
    final t = context.fw;
    final s = context.strings;
    Widget method(String key, String label) => FwChip(
      label: label,
      selected: controller.methods.contains(key),
      onChanged: (_) => controller.toggleMethod(key),
    );
    Widget state(StateFilter filter, String label, [Color? color]) => FwChip(
      label: label,
      color: color,
      selected: controller.states.contains(filter),
      onChanged: (_) => controller.toggleState(filter),
    );
    final gap = const SizedBox(width: 8);
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        children: [
          method('GET', 'GET'),
          gap,
          method('POST', 'POST'),
          gap,
          method('PUT', 'PUT'),
          gap,
          method('PATCH', 'PATCH'),
          gap,
          method('DELETE', 'DELETE'),
          gap,
          method(other, s.filterOtherMethods),
          const SizedBox(width: 14),
          Container(width: 1, color: t.line),
          const SizedBox(width: 14),
          state(StateFilter.success, s.filterSuccess, t.ok),
          gap,
          state(StateFilter.redirect, s.filterRedirect, t.info),
          gap,
          state(StateFilter.clientError, s.filterClientError, t.warning),
          gap,
          state(StateFilter.serverError, s.filterServerError, t.error),
          gap,
          state(StateFilter.failed, s.filterFailed, t.error),
          gap,
          state(StateFilter.running, s.filterRunning, t.copperTone),
          gap,
          state(StateFilter.pinned, s.filterPinned, t.warning),
          if (controller.hasFilters) ...[
            const SizedBox(width: 12),
            TextButton(
              onPressed: controller.clearFilters,
              style: TextButton.styleFrom(
                foregroundColor: t.copperTone,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: Text(s.clearFilters),
            ),
          ],
        ],
      ),
    );
  }
}
