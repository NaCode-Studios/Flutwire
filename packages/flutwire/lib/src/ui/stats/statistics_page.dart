import 'dart:async';

import 'package:flutter/material.dart';

import '../../stats/stats.dart';
import '../../store/store.dart';
import '../detail/call_detail_page.dart';
import '../scope.dart';
import '../shell.dart';
import '../widgets/empty_state.dart';
import '../widgets/segmented_control.dart';
import '../widgets/wire_rule.dart';
import 'summary_view.dart';
import 'timeline_view.dart';

enum _View { summary, timeline }

/// What the history says about itself: its numbers, its slowest calls, how
/// often the calls to each host fail, and the latest calls on a time line.
///
/// The page follows the history, so a call that arrives is counted at once.
class StatisticsPage extends StatefulWidget {
  /// Creates the page.
  const StatisticsPage({super.key});

  @override
  State<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends State<StatisticsPage> {
  late final FlutwireStore _store;
  _View _view = _View.summary;
  late SessionStats _stats;
  late Waterfall _waterfall;
  Timer? _debounce;
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _store = context.session.store;
    _store.calls.addListener(_historyChanged);
    _compute();
  }

  @override
  void dispose() {
    _store.calls.removeListener(_historyChanged);
    _debounce?.cancel();
    _clock?.cancel();
    super.dispose();
  }

  void _historyChanged() {
    // A burst of calls is counted once.
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(_compute);
    });
  }

  void _compute() {
    final calls = _store.calls.value;
    _stats = SessionStats.of(calls);
    _waterfall = Waterfall.of(calls, now: DateTime.now());
    // A call that is running grows on the time line as time goes by.
    final running = calls.any((call) => call.isPending);
    if (running && _clock == null) {
      _clock = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(_compute);
      });
    } else if (!running) {
      _clock?.cancel();
      _clock = null;
    }
  }

  void _open(int id) {
    unawaited(
      Navigator.of(context).push(
        shellRoute(
          context.session,
          name: 'flutwire/call',
          child: CallDetailPage(callId: id),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fw;
    final s = context.strings;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.statistics, style: t.display(size: 20)),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(WireRule.height),
          child: WireRule(),
        ),
      ),
      body: _stats.total == 0
          ? EmptyState(title: s.emptyTitle, message: s.emptyBody)
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                  child: SegmentedControl<_View>(
                    options: {
                      _View.summary: s.statsSummary,
                      _View.timeline: s.statsTimeline,
                    },
                    value: _view,
                    onChanged: (view) => setState(() => _view = view),
                  ),
                ),
                Expanded(
                  child: switch (_view) {
                    _View.summary => SummaryView(stats: _stats, onOpen: _open),
                    _View.timeline => TimelineView(
                      waterfall: _waterfall,
                      onOpen: _open,
                    ),
                  },
                ),
              ],
            ),
    );
  }
}
