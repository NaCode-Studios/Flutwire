import 'dart:async';

import 'package:flutter/material.dart';

import '../../compare/comparison.dart';
import '../../compare/diff.dart';
import '../../l10n/strings.dart';
import '../../model/call.dart';
import '../../session.dart';
import '../../store/store.dart';
import '../../util/format.dart';
import '../detail/call_detail_page.dart';
import '../scope.dart';
import '../shell.dart';
import '../theme/tokens.dart';
import '../widgets/method_chip.dart';
import '../widgets/status_pill.dart';
import '../widgets/toggle_chip.dart';
import '../widgets/wire_rule.dart';
import 'diff_rows.dart';

/// The route that sets two calls side by side, [leftId] on the left.
Route<void> compareRoute(
  FlutwireSession session, {
  required int leftId,
  required int rightId,
}) => shellRoute(
  session,
  name: 'flutwire/compare',
  child: ComparePage(leftId: leftId, rightId: rightId),
);

/// Two calls side by side: the overview, the query, the header fields and the
/// bodies, with what differs marked.
///
/// The page follows the calls while they run, so a response that is still
/// arriving is compared as far as it has come.
class ComparePage extends StatefulWidget {
  /// Compares the call with [leftId], which is side A, against the call with
  /// [rightId], which is side B.
  const ComparePage({super.key, required this.leftId, required this.rightId});

  /// The id of the call on the left.
  final int leftId;

  /// The id of the call on the right.
  final int rightId;

  @override
  State<ComparePage> createState() => _ComparePageState();
}

class _ComparePageState extends State<ComparePage> {
  late final FlutwireStore _store;
  late FlutwireStrings _strings;
  late int _leftId = widget.leftId;
  late int _rightId = widget.rightId;
  FlutwireCall? _left;
  FlutwireCall? _right;
  FlutwireCall? _leftSeen;
  FlutwireCall? _rightSeen;
  Comparison? _comparison;
  bool _gone = false;
  bool _started = false;
  bool _onlyDifferences = true;
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    _store = context.session.store;
    _store.calls.addListener(_historyChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _strings = context.strings;
    if (!_started) {
      _started = true;
      unawaited(_load());
    } else if (_left != null && _right != null) {
      _comparison = Comparison.of(_left!, _right!, _strings);
    }
  }

  @override
  void dispose() {
    _store.calls.removeListener(_historyChanged);
    _refresh?.cancel();
    super.dispose();
  }

  void _historyChanged() {
    final left = _store.find(_leftId);
    final right = _store.find(_rightId);
    if (left == null || right == null) {
      if (mounted && _comparison != null) setState(() => _gone = true);
      return;
    }
    if (identical(left, _leftSeen) && identical(right, _rightSeen)) return;
    // A burst of progress updates is read once.
    _refresh?.cancel();
    _refresh = Timer(
      const Duration(milliseconds: 150),
      () => unawaited(_load()),
    );
  }

  Future<void> _load() async {
    final leftSummary = _store.find(_leftId);
    final rightSummary = _store.find(_rightId);
    final left = await _store.load(_leftId);
    final right = await _store.load(_rightId);
    if (!mounted) return;
    setState(() {
      _leftSeen = leftSummary;
      _rightSeen = rightSummary;
      _left = left;
      _right = right;
      _gone = left == null || right == null;
      _comparison = left == null || right == null
          ? null
          : Comparison.of(left, right, _strings);
    });
  }

  void _swap() {
    setState(() {
      final id = _leftId;
      _leftId = _rightId;
      _rightId = id;
      final call = _left;
      _left = _right;
      _right = call;
      final seen = _leftSeen;
      _leftSeen = _rightSeen;
      _rightSeen = seen;
      _comparison = Comparison.of(_left!, _right!, _strings);
    });
  }

  void _open(int id) {
    unawaited(Navigator.of(context).push(callRoute(context.session, id)));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fw;
    final s = context.strings;
    final comparison = _comparison;
    final left = _left;
    final right = _right;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.compare, style: t.display(size: 20)),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(WireRule.height),
          child: WireRule(),
        ),
        actions: [
          if (comparison != null)
            IconButton(
              tooltip: s.compareSwap,
              icon: const Icon(Icons.swap_horiz_rounded),
              onPressed: _swap,
            ),
        ],
      ),
      body: _gone
          ? Center(
              child: Text(s.callGone, style: t.body(color: t.faint)),
            )
          : comparison == null || left == null || right == null
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _SideCard(
                            label: 'A',
                            call: left,
                            onTap: () => _open(left.id),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _SideCard(
                            label: 'B',
                            call: right,
                            onTap: () => _open(right.id),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: ToggleChip(
                        label: s.compareDifferencesOnly,
                        selected: _onlyDifferences,
                        onChanged: (value) =>
                            setState(() => _onlyDifferences = value),
                      ),
                    ),
                  ),
                ),
                for (final section in comparison.sections) ..._section(section),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: MediaQuery.paddingOf(context).bottom + 32,
                  ),
                ),
              ],
            ),
    );
  }

  /// What a section shows: everything, or only what differs, with a few lines
  /// of what is the same around a difference in a body.
  List<DiffRow> _shown(ComparisonSection section) {
    if (!_onlyDifferences) return section.rows;
    if (section.isIdentical) return const [];
    return section.lines
        ? collapseSame(section.rows)
        : [
            for (final row in section.rows)
              if (row.differs) row,
          ];
  }

  List<Widget> _section(ComparisonSection section) {
    final rows = _shown(section);
    final message = section.message;
    return [
      SliverToBoxAdapter(child: _SectionHeader(section: section)),
      if (message != null)
        SliverToBoxAdapter(
          child: _Message(text: message, differs: !section.isIdentical),
        )
      else
        SliverList.builder(
          itemCount: rows.length,
          itemBuilder: (context, index) =>
              DiffRowView(row: rows[index], lines: section.lines),
        ),
    ];
  }
}

/// The name of a section and how its two sides compare.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.section});

  final ComparisonSection section;

  @override
  Widget build(BuildContext context) {
    final t = context.fw;
    final s = context.strings;
    final identical = section.isIdentical;
    final tone = identical ? t.ok : t.warning;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  section.title.toUpperCase(),
                  style: t.label(color: t.faint),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: t.tint(tone),
                  borderRadius: BorderRadius.circular(FlutwireTokens.radiusXs),
                ),
                child: Text(
                  identical
                      ? s.compareIdentical
                      : s.compareDifferences(section.differences),
                  style: t.mono(
                    size: 11,
                    weight: FontWeight.w600,
                    color: tone,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
          for (final note in section.notes)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(note, style: t.body(size: 12, color: t.faint)),
            ),
        ],
      ),
    );
  }
}

/// A sentence in place of rows, for bodies that are not text.
class _Message extends StatelessWidget {
  const _Message({required this.text, required this.differs});

  final String text;
  final bool differs;

  @override
  Widget build(BuildContext context) {
    final t = context.fw;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 2, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: differs ? t.tint(t.warning) : t.surface,
        borderRadius: BorderRadius.circular(FlutwireTokens.radiusMd),
        border: Border.all(color: t.line),
      ),
      child: Text(text, style: t.mono(size: 12.5, color: t.ink)),
    );
  }
}

/// One of the two calls, as a card that opens it.
class _SideCard extends StatelessWidget {
  const _SideCard({
    required this.label,
    required this.call,
    required this.onTap,
  });

  final String label;
  final FlutwireCall call;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.fw;
    final path = call.uri.path.isEmpty ? '/' : call.uri.path;
    return Material(
      color: t.surface,
      borderRadius: BorderRadius.circular(FlutwireTokens.radiusLg),
      child: InkWell(
        borderRadius: BorderRadius.circular(FlutwireTokens.radiusLg),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(FlutwireTokens.radiusLg),
            border: Border.all(color: t.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(label, style: t.label(color: t.copperTone)),
                  const SizedBox(width: 8),
                  MethodChip(call.method),
                  const Spacer(),
                  StatusPill(call: call),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                call.graphql?.operationName ?? path,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: t.mono(
                  size: 12.5,
                  weight: FontWeight.w600,
                  color: t.ink,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                call.host,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.body(size: 11.5, color: t.muted),
              ),
              const SizedBox(height: 6),
              Text(
                '${formatClock(call.startedAt)}  ${formatDuration(call.duration)}',
                style: t.mono(size: 11.5, color: t.faint),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
