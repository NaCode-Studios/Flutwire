import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../scope.dart';
import '../theme/tokens.dart';
import 'code_layout.dart';
import 'highlight.dart';
import 'metrics.dart';
import 'search.dart';
import 'search_follow.dart';

/// Text as rows of fixed height, drawn lazily.
///
/// This is the view behind the pretty, raw and decoded modes. Every row is
/// [BodyMetrics.lineHeight] tall, so the list is a plain virtualised list, only
/// the rows on screen are built, and the row of a search match is found with a
/// multiplication. A line longer than [bodyMaxRowChars] is cut into several
/// rows, in every mode, so a minified body that is one line of a quarter of a
/// million characters never becomes one text object.
///
/// Visible text can be selected and copied. Selection is limited to the rows
/// that are built, which are the rows on screen and a few around them: a drag
/// that reaches past them scrolls, and the selection follows as rows are built.
class CodeView extends StatefulWidget {
  /// Shows [text] in [language]'s colours.
  const CodeView({
    super.key,
    required this.text,
    required this.language,
    required this.wrap,
    required this.lineNumbers,
    required this.search,
  });

  /// The text to show.
  final String text;

  /// The syntax to colour.
  final CodeLanguage language;

  /// Whether long lines wrap. When false the view scrolls sideways.
  final bool wrap;

  /// Whether each line carries its number.
  final bool lineNumbers;

  /// The search whose matches are highlighted.
  final BodySearchController search;

  @override
  State<CodeView> createState() => _CodeViewState();
}

class _CodeViewState extends State<CodeView> with BodyMetricsState<CodeView> {
  static const double _verticalPadding = 8;

  /// The 2 px bar that marks a continued line, and the gap after it.
  static const double _leading = 10;
  static const double _trailing = 12;

  final ScrollController _vertical = ScrollController();
  final ScrollController _horizontal = ScrollController();

  CodeLayout? _layout;
  CodeHighlighter? _highlighter;
  int _cells = -2;
  int _lineCount = 0;
  double _gutter = 0;

  final CurrentMatchTracker _tracker = CurrentMatchTracker();

  @override
  void initState() {
    super.initState();
    _lineCount = CodeLayout.lineCountOf(widget.text);
    widget.search.addListener(_onSearch);
  }

  @override
  void didUpdateWidget(CodeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.search != widget.search) {
      oldWidget.search.removeListener(_onSearch);
      widget.search.addListener(_onSearch);
    }
    if (!identical(oldWidget.text, widget.text)) {
      _layout = null;
      _highlighter = null;
      _lineCount = CodeLayout.lineCountOf(widget.text);
    } else if (oldWidget.language != widget.language) {
      _highlighter = null;
    }
  }

  @override
  void dispose() {
    widget.search.removeListener(_onSearch);
    _vertical.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  double _gutterWidth(BodyMetrics m) => '$_lineCount'.length * m.charWidth + 16;

  CodeLayout _layoutFor(int cells) {
    var layout = _layout;
    if (layout != null && cells == _cells) return layout;
    // Wrapping, unwrapping or turning the phone changes how many rows come
    // before any given text, so remember which text was at the top of the
    // screen and put it back there.
    var anchor = -1;
    if (layout != null && _vertical.hasClients && layout.rowCount > 0) {
      final top = ((_vertical.offset - _verticalPadding) / metrics.lineHeight)
          .floor();
      anchor = layout.start(math.max(0, math.min(top, layout.rowCount - 1)));
    }
    layout = CodeLayout.build(widget.text, maxCells: cells < 0 ? null : cells);
    _layout = layout;
    _cells = cells;
    _highlighter = null;
    if (anchor >= 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final current = _layout;
        if (!mounted || current == null || !_vertical.hasClients) return;
        _jumpToRow(current.rowAt(anchor), center: false);
      });
    }
    return layout;
  }

  void _jumpToRow(int row, {required bool center}) {
    final position = _vertical.position;
    final top = _verticalPadding + row * metrics.lineHeight;
    final target = center
        ? top - (position.viewportDimension - metrics.lineHeight) / 2
        : top - _verticalPadding;
    _vertical.jumpTo(
      math.min(
        math.max(target, position.minScrollExtent),
        position.maxScrollExtent,
      ),
    );
  }

  void _onSearch() {
    if (_tracker.advance(widget.search) == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _revealCurrent();
    });
  }

  /// Brings the match the search is on into view, in both directions.
  void _revealCurrent() {
    final layout = _layout;
    final search = widget.search;
    if (layout == null || layout.rowCount == 0 || search.current < 0) return;
    final match = search.matches[search.current];
    final row = layout.rowAt(match.start);
    final m = metrics;
    if (_vertical.hasClients) {
      final position = _vertical.position;
      final top = _verticalPadding + row * m.lineHeight;
      final visible = position.pixels;
      if (top < visible ||
          top + m.lineHeight > visible + position.viewportDimension) {
        _jumpToRow(row, center: true);
      }
    }
    if (!widget.wrap && _horizontal.hasClients) {
      final position = _horizontal.position;
      final left =
          _leading + _gutter + (match.start - layout.start(row)) * m.charWidth;
      final right = left + search.matchLength * m.charWidth;
      if (left < position.pixels ||
          right > position.pixels + position.viewportDimension) {
        _horizontal.jumpTo(
          math.min(
            math.max(left - 48, position.minScrollExtent),
            position.maxScrollExtent,
          ),
        );
      }
    }
  }

  List<MatchMark> _marksFor(int row, CodeLayout layout) {
    final search = widget.search;
    final matches = search.matches;
    if (matches.isEmpty) return const [];
    final length = search.matchLength;
    final rowStart = layout.start(row);
    final rowEnd = layout.end(row);
    // The first match that ends after the row begins.
    var lo = 0;
    var hi = matches.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (matches[mid].start + length <= rowStart) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    final marks = <MatchMark>[];
    for (var i = lo; i < matches.length && matches[i].start < rowEnd; i++) {
      marks.add((
        start: math.max(matches[i].start, rowStart),
        end: math.min(matches[i].start + length, rowEnd),
        current: i == search.current,
      ));
    }
    return marks;
  }

  Widget _buildRow(
    int row,
    CodeLayout layout,
    CodeHighlighter highlighter,
    FlutwireTokens tokens,
  ) {
    final m = metrics;
    final spans = styledSpans(
      text: layout.text,
      start: layout.start(row),
      end: layout.end(row),
      tokens: tokens,
      runs: highlighter.runsFor(row),
      marks: _marksFor(row, layout),
    );
    final first = layout.isFirstOfLine(row);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // A bar down the left edge of every row after the first of a cut line.
        // Together the rows read as one line that wraps, in both modes.
        SizedBox(
          width: 2,
          child: first ? null : ColoredBox(color: tokens.lineStrong),
        ),
        const SizedBox(width: _leading - 2),
        if (_gutter > 0)
          // Numbers are not text anyone means to copy.
          SelectionContainer.disabled(
            child: SizedBox(
              width: _gutter,
              child: first
                  ? Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(
                        '${layout.line(row) + 1}',
                        textAlign: TextAlign.end,
                        maxLines: 1,
                        softWrap: false,
                        style: m.style.copyWith(color: tokens.faint),
                        strutStyle: m.strut,
                        textScaler: TextScaler.noScaling,
                      ),
                    )
                  : null,
            ),
          ),
        Expanded(
          child: Text.rich(
            TextSpan(children: spans),
            style: m.style,
            strutStyle: m.strut,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.clip,
            textScaler: TextScaler.noScaling,
          ),
        ),
        const SizedBox(width: _trailing),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.fw;
    final m = metrics;
    return LayoutBuilder(
      builder: (context, box) {
        _gutter = widget.lineNumbers ? _gutterWidth(m) : 0;
        final cells = widget.wrap
            ? math.max(
                8,
                m.cellsIn(box.maxWidth - _leading - _gutter - _trailing),
              )
            : -1;
        final layout = _layoutFor(cells);
        final highlighter = _highlighter ??= CodeHighlighter(
          layout,
          SyntaxLexer.of(widget.language),
        );
        Widget list = ListenableBuilder(
          listenable: widget.search,
          builder: (context, _) => ListView.builder(
            controller: _vertical,
            itemExtent: m.lineHeight,
            itemCount: layout.rowCount,
            padding: const EdgeInsets.symmetric(vertical: _verticalPadding),
            addAutomaticKeepAlives: false,
            itemBuilder: (context, row) =>
                _buildRow(row, layout, highlighter, tokens),
          ),
        );
        if (!widget.wrap) {
          // The face is monospaced, so the widest row is as wide as its widest
          // count of cells, and the scroll extent is known without measuring
          // any text.
          final width = math.max(
            box.maxWidth,
            _leading + _gutter + layout.maxCells * m.charWidth + _trailing + 2,
          );
          list = SingleChildScrollView(
            controller: _horizontal,
            scrollDirection: Axis.horizontal,
            child: SizedBox(width: width, child: list),
          );
        }
        return SelectionArea(child: list);
      },
    );
  }
}
