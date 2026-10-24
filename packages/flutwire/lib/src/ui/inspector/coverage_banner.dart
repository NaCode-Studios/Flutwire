import 'dart:async';

import 'package:flutter/material.dart';

import '../../coverage.dart';
import '../scope.dart';
import '../shell.dart';
import '../theme/tokens.dart';

/// The line above the list that says Flutwire may be missing calls, and which a
/// tap turns into the reasons. It is not there while nothing is wrong.
class CoverageBanner extends StatelessWidget {
  /// Creates the banner.
  const CoverageBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.session;
    return ValueListenableBuilder<List<FlutwireCoverageNote>>(
      valueListenable: session.coverage,
      builder: (context, notes, _) {
        if (notes.isEmpty) return const SizedBox(width: double.infinity);
        final t = context.fw;
        final s = context.strings;
        final shape = RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FlutwireTokens.radiusMd),
          side: BorderSide(color: t.warning.withValues(alpha: 0.35)),
        );
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Material(
            color: t.warning.withValues(alpha: 0.10),
            shape: shape,
            child: InkWell(
              customBorder: shape,
              onTap: () => unawaited(showCoverageSheet(context)),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                child: Row(
                  children: [
                    Icon(
                      Icons.visibility_off_outlined,
                      size: 18,
                      color: t.warning,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        s.coverageBanner,
                        style: t.body(size: 13, color: t.ink),
                      ),
                    ),
                    Text(
                      s.coverageDetails,
                      style: t.body(
                        size: 13,
                        weight: FontWeight.w600,
                        color: t.warning,
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: t.warning,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Opens the reasons Flutwire may be missing calls as a sheet over the
/// inspector.
Future<void> showCoverageSheet(BuildContext context) {
  final session = context.session;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    elevation: 0,
    showDragHandle: false,
    builder: (_) =>
        FlutwireShell(session: session, child: const _CoverageSheet()),
  );
}

class _CoverageSheet extends StatelessWidget {
  const _CoverageSheet();

  @override
  Widget build(BuildContext context) {
    final t = context.fw;
    final s = context.strings;
    final session = context.session;
    return Material(
      color: t.surface,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(FlutwireTokens.radiusXl),
        ),
      ),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.85,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: ValueListenableBuilder<List<FlutwireCoverageNote>>(
              valueListenable: session.coverage,
              builder: (context, notes, _) => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 32,
                      height: 4,
                      margin: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: t.lineStrong,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Text(s.coverageTitle, style: t.display(size: 22)),
                  const SizedBox(height: 16),
                  for (final note in notes) ...[
                    _Note(note: note),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.note});

  final FlutwireCoverageNote note;

  @override
  Widget build(BuildContext context) {
    final t = context.fw;
    final s = context.strings;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.ground,
        borderRadius: BorderRadius.circular(FlutwireTokens.radiusMd),
        border: Border.all(color: t.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s.coverageGapTitle(note.gap),
            style: t.body(size: 15, weight: FontWeight.w600, color: t.ink),
          ),
          const SizedBox(height: 6),
          Text(
            s.coverageGapWhat(note.gap, note.subject),
            style: t.body(size: 13.5, color: t.muted),
          ),
          const SizedBox(height: 8),
          Text(
            s.coverageGapFix(note.gap),
            style: t.body(size: 13.5, color: t.ink),
          ),
          // A replaced capture is a state that every check finds again, not a
          // number of calls, so counting it would read as calls it lost.
          if (note.gap != FlutwireGap.captureReplaced) ...[
            const SizedBox(height: 10),
            Text(
              s.coverageSeen(note.count).toUpperCase(),
              style: t.label(color: t.faint),
            ),
          ],
        ],
      ),
    );
  }
}
