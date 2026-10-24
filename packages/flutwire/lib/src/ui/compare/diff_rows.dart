import 'package:flutter/material.dart';

import '../../compare/diff.dart';
import '../scope.dart';

enum _Side { left, right }

/// One row of a comparison: the two sides next to each other, with what
/// differs tinted and marked, so that colour is not all that tells the sides
/// apart.
class DiffRowView extends StatelessWidget {
  /// Creates the view of [row]. [lines] says the row is a line of two bodies,
  /// which has no name and no word for a side that has nothing.
  const DiffRowView({super.key, required this.row, required this.lines});

  /// What to show.
  final DiffRow row;

  /// Whether the row is a line of a body rather than a named field.
  final bool lines;

  @override
  Widget build(BuildContext context) {
    final t = context.fw;
    if (row.kind == DiffKind.skipped) return _Skipped(count: row.count);
    final cells = IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _Cell(row: row, side: _Side.left, lines: lines),
          ),
          SizedBox(width: 1, child: ColoredBox(color: t.line)),
          Expanded(
            child: _Cell(row: row, side: _Side.right, lines: lines),
          ),
        ],
      ),
    );
    final name = row.name;
    return Semantics(
      container: true,
      label: _describe(),
      child: ExcludeSemantics(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, name == null ? 0 : 8, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (name != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    name,
                    style: t.mono(
                      size: 11.5,
                      weight: FontWeight.w600,
                      color: t.syntaxKey,
                    ),
                  ),
                ),
              cells,
            ],
          ),
        ),
      ),
    );
  }

  String _describe() => [
    ?row.name,
    if (row.left != null) 'A: ${row.left}',
    if (row.right != null) 'B: ${row.right}',
  ].join(', ');
}

class _Cell extends StatelessWidget {
  const _Cell({required this.row, required this.side, required this.lines});

  final DiffRow row;
  final _Side side;
  final bool lines;

  String? get _text => side == _Side.left ? row.left : row.right;

  @override
  Widget build(BuildContext context) {
    final t = context.fw;
    final s = context.strings;
    final text = _text;
    final differs = switch (row.kind) {
      DiffKind.changed => true,
      DiffKind.onlyLeft => side == _Side.left,
      DiffKind.onlyRight => side == _Side.right,
      DiffKind.same || DiffKind.skipped => false,
    };
    final tone = side == _Side.left ? t.error : t.ok;
    final base = t.mono(size: 12, color: t.ink);
    final Widget content;
    if (text == null) {
      // A body has no word for the lines the other side added, which would
      // only repeat itself down the column.
      content = lines
          ? Text(' ', style: base)
          : Text(
              s.compareMissing,
              style: t
                  .body(size: 12, color: t.faint)
                  .copyWith(fontStyle: FontStyle.italic),
            );
    } else {
      content = Text.rich(_spans(text, base, tone, differs));
    }
    return DecoratedBox(
      decoration: BoxDecoration(color: differs ? t.tint(tone) : null),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 6, 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 12,
              child: Text(
                differs ? (side == _Side.left ? '−' : '+') : '',
                style: t.mono(size: 12, weight: FontWeight.w700, color: tone),
              ),
            ),
            Expanded(child: content),
          ],
        ),
      ),
    );
  }

  /// The text, with the part that changed marked when both sides have a line
  /// and it is one line.
  TextSpan _spans(String text, TextStyle base, Color tone, bool differs) {
    final left = row.left;
    final right = row.right;
    final comparable =
        row.kind == DiffKind.changed &&
        left != null &&
        right != null &&
        !left.contains('\n') &&
        !right.contains('\n');
    if (!comparable) {
      return TextSpan(text: text.isEmpty ? ' ' : text, style: base);
    }
    final span = changedSpan(left, right);
    final end = side == _Side.left ? span.leftEnd : span.rightEnd;
    if (end <= span.start) return TextSpan(text: text, style: base);
    return TextSpan(
      style: base,
      children: [
        TextSpan(text: text.substring(0, span.start)),
        TextSpan(
          text: text.substring(span.start, end),
          style: TextStyle(
            backgroundColor: tone.withValues(alpha: 0.34),
            fontWeight: FontWeight.w700,
          ),
        ),
        TextSpan(text: text.substring(end)),
      ],
    );
  }
}

/// The place where a run of lines that are the same was left out.
class _Skipped extends StatelessWidget {
  const _Skipped({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final t = context.fw;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      padding: const EdgeInsets.symmetric(vertical: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: t.raised,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        context.strings.compareSkipped(count),
        style: t.mono(size: 11, color: t.faint),
      ),
    );
  }
}
