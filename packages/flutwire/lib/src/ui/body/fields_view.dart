import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../scope.dart';
import 'copy.dart';
import 'highlight.dart';
import 'metrics.dart';
import 'quiet_note.dart';
import 'reveal.dart';
import 'search.dart';

/// The fields of a form body, and the text a search runs through.
///
/// Unit `2 * i` is the key of field `i` and `2 * i + 1` its value, cut at
/// [bodyTextLimit] characters, the most the view will draw.
final class FieldsModel implements BodySearchSource {
  /// Wraps [fields], in the order they were sent.
  const FieldsModel(this.fields);

  /// The decoded fields.
  final List<MapEntry<String, String>> fields;

  @override
  void forEachUnit(bool Function(int unit, String text) visit) {
    for (var i = 0; i < fields.length; i++) {
      if (!visit(i * 2, fields[i].key)) return;
      final value = fields[i].value;
      final text = value.length > bodyTextLimit
          ? value.substring(0, bodyTextLimit)
          : value;
      if (!visit(i * 2 + 1, text)) return;
    }
  }
}

/// The fields of a form body as a list: the name in the muted mono face, the
/// value in the ink one. Tapping or pressing a field copies its value.
class FieldsView extends StatefulWidget {
  /// Shows the fields of [model].
  const FieldsView({super.key, required this.model, required this.search});

  /// The fields.
  final FieldsModel model;

  /// The search whose matches are highlighted and revealed.
  final BodySearchController search;

  @override
  State<FieldsView> createState() => _FieldsViewState();
}

class _FieldsViewState extends State<FieldsView> {
  final ScrollController _scroll = ScrollController();
  late final RowRevealer _revealer = RowRevealer(_scroll);
  final Set<int> _opened = {};

  Map<int, List<int>> _byRow = const {};
  List<BodyMatch>? _mapFor;
  List<BodyMatch>? _revealedFor;
  int _revealedIndex = -2;

  @override
  void initState() {
    super.initState();
    widget.search.addListener(_onSearch);
  }

  @override
  void didUpdateWidget(FieldsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.search != widget.search) {
      oldWidget.search.removeListener(_onSearch);
      widget.search.addListener(_onSearch);
    }
  }

  @override
  void dispose() {
    widget.search.removeListener(_onSearch);
    _scroll.dispose();
    super.dispose();
  }

  void _onSearch() {
    final search = widget.search;
    if (!identical(search.source, widget.model)) return;
    if (search.current < 0) {
      _revealedFor = search.matches;
      _revealedIndex = -1;
      return;
    }
    if (identical(_revealedFor, search.matches) &&
        _revealedIndex == search.current) {
      return;
    }
    _revealedFor = search.matches;
    _revealedIndex = search.current;
    final match = search.matches[search.current];
    final row = match.unit >> 1;
    setState(() {
      // A match in the part of a long value that is cut away opens the value.
      if (match.unit.isOdd &&
          match.start + search.matchLength > bodyPreviewChars) {
        _opened.add(row);
      }
    });
    _revealer.reveal(
      row,
      itemCount: widget.model.fields.length,
      isMounted: () => mounted,
    );
  }

  void _syncMarks() {
    final matches = widget.search.matches;
    if (identical(matches, _mapFor)) return;
    _mapFor = matches;
    final map = <int, List<int>>{};
    for (var i = 0; i < matches.length; i++) {
      (map[matches[i].unit >> 1] ??= <int>[]).add(i);
    }
    _byRow = map;
  }

  List<MatchMark> _marksOf(int row, {required bool value}) {
    final indices = _byRow[row];
    if (indices == null) return const [];
    final search = widget.search;
    return [
      for (final i in indices)
        if (search.matches[i].unit.isOdd == value)
          (
            start: search.matches[i].start,
            end: search.matches[i].start + search.matchLength,
            current: i == search.current,
          ),
    ];
  }

  Widget _buildRow(BuildContext context, int index, double width) {
    final tokens = context.fw;
    final strings = context.strings;
    final entry = widget.model.fields[index];
    final value = entry.value;
    final open = _opened.contains(index);
    final limit = open ? bodyTextLimit : bodyPreviewChars;
    final shown = value.length > limit ? value.substring(0, limit) : value;
    final key = Text.rich(
      TextSpan(
        children: styledSpans(
          text: entry.key,
          start: 0,
          end: entry.key.length,
          tokens: tokens,
          marks: _marksOf(index, value: false),
        ),
      ),
      style: tokens.mono(size: 12, color: tokens.muted),
    );
    final text = Text.rich(
      TextSpan(
        children: [
          ...styledSpans(
            text: shown,
            start: 0,
            end: shown.length,
            tokens: tokens,
            marks: _marksOf(index, value: true),
          ),
          if (shown.length < value.length) const TextSpan(text: '…'),
        ],
      ),
      style: tokens.mono(size: 13, color: tokens.ink),
    );
    final more = value.length > bodyPreviewChars
        ? InkWell(
            onTap: () => setState(() {
              if (!_opened.remove(index)) _opened.add(index);
            }),
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 40,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  open ? strings.showLess : strings.showMore,
                  style: tokens.body(
                    size: 12,
                    weight: FontWeight.w600,
                    color: tokens.syntaxKey,
                  ),
                ),
              ),
            ),
          )
        : null;
    final keyWidth = math.min(280.0, math.max(140.0, width * 0.28));
    final body = width < bodyNarrowWidth
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [key, const SizedBox(height: 4), text, ?more],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: keyWidth, child: key),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [text, ?more],
                ),
              ),
            ],
          );
    void copyValue() => copyToClipboard(context, value);
    return KeyedSubtree(
      key: _revealer.keyFor(index),
      child: InkWell(
        onTap: copyValue,
        onLongPress: copyValue,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: tokens.line)),
          ),
          child: body,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fields = widget.model.fields;
    if (fields.isEmpty) return QuietNote(context.strings.bodyEmpty);
    return LayoutBuilder(
      builder: (context, box) => ListenableBuilder(
        listenable: widget.search,
        builder: (context, _) {
          _syncMarks();
          return ListView.builder(
            controller: _scroll,
            itemCount: fields.length,
            itemBuilder: (context, index) =>
                _buildRow(context, index, box.maxWidth),
          );
        },
      ),
    );
  }
}
