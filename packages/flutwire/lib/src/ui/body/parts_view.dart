import 'package:flutter/material.dart';

import '../../model/body.dart';
import '../../model/multipart.dart';
import '../../util/format.dart';
import '../scope.dart';
import 'highlight.dart';
import 'metrics.dart';
import 'quiet_note.dart';
import 'reveal.dart';
import 'search.dart';

/// The parts of a multipart body, read once, and the text a search runs
/// through.
///
/// Unit `3 * i` is the name of part `i`, `3 * i + 1` its file name and
/// `3 * i + 2` its text, cut at [bodyTextLimit] characters.
final class PartsModel implements BodySearchSource {
  /// Splits [body] into its parts.
  PartsModel(FlutwireBody body) : parts = parseMultipart(body);

  /// The parts that arrived, in order.
  final List<FlutwireMultipartPart> parts;

  /// The text of each part, or null when the part is not text. It is decoded
  /// once here because decoding is not free and a list rebuilds often.
  late final List<String?> texts = [for (final part in parts) part.text];

  /// Whether each part is an image the view can draw.
  late final List<bool> images = [
    for (final part in parts)
      FlutwireBody(bytes: part.bytes, contentType: part.contentType).kind ==
          FlutwireBodyKind.image,
  ];

  @override
  void forEachUnit(bool Function(int unit, String text) visit) {
    for (var i = 0; i < parts.length; i++) {
      final name = parts[i].name;
      if (name != null && !visit(i * 3, name)) return;
      final file = parts[i].filename;
      if (file != null && !visit(i * 3 + 1, file)) return;
      final text = texts[i];
      if (text != null &&
          !visit(
            i * 3 + 2,
            text.length > bodyTextLimit
                ? text.substring(0, bodyTextLimit)
                : text,
          )) {
        return;
      }
    }
  }
}

/// A multipart body as one card per part: its name, whether it is a file, its
/// type and size, and a look at what it holds.
class PartsView extends StatefulWidget {
  /// Shows the parts of [model].
  const PartsView({super.key, required this.model, required this.search});

  /// The parts.
  final PartsModel model;

  /// The search whose matches are highlighted and revealed.
  final BodySearchController search;

  @override
  State<PartsView> createState() => _PartsViewState();
}

class _PartsViewState extends State<PartsView> {
  /// The tallest an image preview gets.
  static const double _previewHeight = 140;

  final ScrollController _scroll = ScrollController();
  late final RowRevealer _revealer = RowRevealer(_scroll);
  final Set<int> _opened = {};

  Map<int, List<int>> _byPart = const {};
  List<BodyMatch>? _mapFor;
  List<BodyMatch>? _revealedFor;
  int _revealedIndex = -2;

  @override
  void initState() {
    super.initState();
    widget.search.addListener(_onSearch);
  }

  @override
  void didUpdateWidget(PartsView oldWidget) {
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
    final part = match.unit ~/ 3;
    setState(() {
      if (match.unit % 3 == 2 &&
          match.start + search.matchLength > bodyPreviewChars) {
        _opened.add(part);
      }
    });
    // Row 0 is the heading, so part `i` is row `i + 1`.
    _revealer.reveal(
      part + 1,
      itemCount: widget.model.parts.length + 1,
      isMounted: () => mounted,
    );
  }

  void _syncMarks() {
    final matches = widget.search.matches;
    if (identical(matches, _mapFor)) return;
    _mapFor = matches;
    final map = <int, List<int>>{};
    for (var i = 0; i < matches.length; i++) {
      (map[matches[i].unit ~/ 3] ??= <int>[]).add(i);
    }
    _byPart = map;
  }

  /// The marks of part [part]'s field number [field]: 0 name, 1 file name,
  /// 2 text.
  List<MatchMark> _marksOf(int part, int field) {
    final indices = _byPart[part];
    if (indices == null) return const [];
    final search = widget.search;
    return [
      for (final i in indices)
        if (search.matches[i].unit % 3 == field)
          (
            start: search.matches[i].start,
            end: search.matches[i].start + search.matchLength,
            current: i == search.current,
          ),
    ];
  }

  Widget _spans(
    String text,
    int part,
    int field,
    TextStyle style,
    BuildContext context, {
    bool cut = false,
  }) {
    return Text.rich(
      TextSpan(
        children: [
          ...styledSpans(
            text: text,
            start: 0,
            end: text.length,
            tokens: context.fw,
            marks: _marksOf(part, field),
          ),
          if (cut) const TextSpan(text: '…'),
        ],
      ),
      style: style,
    );
  }

  Widget _preview(BuildContext context, int index) {
    final tokens = context.fw;
    final strings = context.strings;
    final model = widget.model;
    final part = model.parts[index];
    if (model.images[index]) {
      return Align(
        alignment: Alignment.centerLeft,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: _previewHeight),
            child: Image.memory(
              part.bytes,
              fit: BoxFit.contain,
              alignment: Alignment.centerLeft,
              errorBuilder: (context, error, stack) => Text(
                strings.imageFailed,
                style: tokens.body(size: 12, color: tokens.faint),
              ),
            ),
          ),
        ),
      );
    }
    final text = model.texts[index];
    if (text == null) return const SizedBox.shrink();
    final open = _opened.contains(index);
    final limit = open ? bodyTextLimit : bodyPreviewChars;
    final shown = text.length > limit ? text.substring(0, limit) : text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _spans(
          shown,
          index,
          2,
          tokens.mono(size: 12.5, color: tokens.text),
          context,
          cut: shown.length < text.length,
        ),
        if (text.length > bodyPreviewChars)
          InkWell(
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
          ),
      ],
    );
  }

  Widget _card(BuildContext context, int index) {
    final tokens = context.fw;
    final strings = context.strings;
    final part = widget.model.parts[index];
    final name = part.name ?? '#${index + 1}';
    final meta = [
      if (part.contentType != null) part.contentType!,
      formatBytes(part.bytes.length),
    ].join('  ·  ');
    final file = part.filename;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tokens.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _spans(
                  name,
                  index,
                  0,
                  tokens.mono(
                    size: 13,
                    weight: FontWeight.w600,
                    color: tokens.ink,
                  ),
                  context,
                ),
              ),
              if (part.isFile) ...[
                const SizedBox(width: 8),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: tokens.tint(tokens.info),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    child: Text(
                      strings.filePart,
                      style: tokens.label(color: tokens.info),
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (file != null) ...[
            const SizedBox(height: 4),
            _spans(
              file,
              index,
              1,
              tokens.mono(size: 12, color: tokens.muted),
              context,
            ),
          ],
          const SizedBox(height: 4),
          Text(meta, style: tokens.mono(size: 11.5, color: tokens.faint)),
          const SizedBox(height: 10),
          _preview(context, index),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final tokens = context.fw;
    final parts = widget.model.parts;
    if (parts.isEmpty) return QuietNote(strings.bodyEmpty);
    return ListenableBuilder(
      listenable: widget.search,
      builder: (context, _) {
        _syncMarks();
        return ListView.builder(
          controller: _scroll,
          itemCount: parts.length + 1,
          padding: const EdgeInsets.only(bottom: 8),
          itemBuilder: (context, row) {
            if (row == 0) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: Text(
                  strings.partsCount(parts.length),
                  style: tokens.label(),
                ),
              );
            }
            return KeyedSubtree(
              key: _revealer.keyFor(row),
              child: _card(context, row - 1),
            );
          },
        );
      },
    );
  }
}
