import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../scope.dart';
import '../theme/tokens.dart';
import 'copy.dart';
import 'highlight.dart';
import 'json_model.dart';
import 'metrics.dart';
import 'search.dart';

enum _NodeAction { copyValue, copyPath }

/// A JSON document as a tree of rows, drawn lazily.
///
/// Every row is the same height, so the tree is a plain virtualised list over
/// the rows that are open. A string too long for one row is shown cut, and when
/// it is opened it takes as many extra rows as it needs, each a fixed number of
/// characters, which keeps a string of a hundred thousand characters from ever
/// being one text object.
class JsonTree extends StatefulWidget {
  /// Shows the document held by [controller].
  const JsonTree({super.key, required this.controller, required this.search});

  /// The document and which of its nodes are open.
  final JsonTreeController controller;

  /// The search whose matches are highlighted and revealed.
  final BodySearchController search;

  @override
  State<JsonTree> createState() => _JsonTreeState();
}

class _JsonTreeState extends State<JsonTree> with BodyMetricsState<JsonTree> {
  static const double _indentStep = 14;
  static const double _chevronBox = 18;
  static const double _padLeft = 8;
  static const double _padRight = 4;
  static const double _menuWidth = 40;
  static const double _controlWidth = 84;
  static const double _verticalPadding = 6;

  final ScrollController _vertical = ScrollController();

  Int32List _nodes = Int32List(0);
  Int32List _subs = Int32List(0);
  bool _stale = true;
  double _width = -1;
  bool _narrow = false;
  double _rowHeight = 28;
  double _charWidth = 0;

  Map<int, List<int>> _matchesByNode = const {};
  List<BodyMatch>? _mapFor;
  List<BodyMatch>? _revealedFor;
  int _revealedIndex = -2;
  Offset _lastTap = Offset.zero;

  JsonTreeController get _tree => widget.controller;

  @override
  void initState() {
    super.initState();
    _tree.addListener(_onTree);
    widget.search.addListener(_onSearch);
  }

  @override
  void didUpdateWidget(JsonTree oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onTree);
      widget.controller.addListener(_onTree);
      _stale = true;
    }
    if (oldWidget.search != widget.search) {
      oldWidget.search.removeListener(_onSearch);
      widget.search.addListener(_onSearch);
    }
  }

  @override
  void dispose() {
    _tree.removeListener(_onTree);
    widget.search.removeListener(_onSearch);
    _vertical.dispose();
    super.dispose();
  }

  void _onTree() {
    if (mounted) setState(() => _stale = true);
  }

  double _leading(int depth) => depth * _indentStep + _chevronBox;

  /// How many characters fit on each row after the first of an opened string.
  int _restChars(int depth) => math.max(
    8,
    metrics.cellsIn(_width - _padLeft - _leading(depth) - _padRight),
  );

  /// How many characters of an opened string fit on its first row, which also
  /// holds the key and, on a phone, the menu button.
  int _firstChars(int node) {
    final model = _tree.model;
    var room = _width - _padLeft - _leading(model.depth[node]) - _padRight;
    if (_narrow) room -= _menuWidth;
    final value = model.values[node];
    if (value is String && value.length > jsonStringCut) {
      room -= _controlWidth;
    }
    final prefix = node == 0 ? 0 : model.keyLabel(node).length + 2;
    return math.max(8, metrics.cellsIn(room) - prefix);
  }

  int _extraRows(int node) {
    final whole = _tree.wholeText(node);
    if (whole == null) return 0;
    return JsonTreeController.rowsFor(
          whole.length,
          first: _firstChars(node),
          rest: _restChars(_tree.model.depth[node]),
        ) -
        1;
  }

  void _layoutFor(double width) {
    final m = metrics;
    final narrow = width < bodyNarrowWidth;
    final changed =
        _stale ||
        width != _width ||
        narrow != _narrow ||
        m.charWidth != _charWidth;
    _width = width;
    _narrow = narrow;
    _charWidth = m.charWidth;
    _rowHeight = ((narrow ? 40 : 28) * m.lineHeight / bodyLineHeight)
        .roundToDouble();
    if (!changed) return;
    _stale = false;
    final model = _tree.model;
    final nodes = <int>[];
    final subs = <int>[];
    var i = 0;
    while (i < model.length) {
      nodes.add(i);
      subs.add(0);
      if (!model.isContainer(i)) {
        final extra = _extraRows(i);
        for (var k = 1; k <= extra; k++) {
          nodes.add(i);
          subs.add(k);
        }
        i++;
      } else if (_tree.isExpanded(i)) {
        i++;
      } else {
        i = model.end[i];
      }
    }
    _nodes = Int32List.fromList(nodes);
    _subs = Int32List.fromList(subs);
  }

  /// The index of the first row that shows [node].
  int _firstRowOf(int node) {
    var lo = 0;
    var hi = _nodes.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_nodes[mid] < node) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  void _syncMarks() {
    final matches = widget.search.matches;
    if (identical(matches, _mapFor)) return;
    _mapFor = matches;
    final map = <int, List<int>>{};
    for (var i = 0; i < matches.length; i++) {
      (map[matches[i].unit >> 1] ??= <int>[]).add(i);
    }
    _matchesByNode = map;
  }

  List<MatchMark> _marksOf(int node, {required bool value, int shift = 0}) {
    final indices = _matchesByNode[node];
    if (indices == null) return const [];
    final search = widget.search;
    final length = search.matchLength;
    return [
      for (final i in indices)
        if (search.matches[i].unit.isOdd == value)
          (
            start: search.matches[i].start + shift,
            end: search.matches[i].start + shift + length,
            current: i == search.current,
          ),
    ];
  }

  void _onSearch() {
    final search = widget.search;
    if (!identical(search.source, _tree)) return;
    if (!identical(_revealedFor, search.matches)) {
      _revealedFor = search.matches;
      _revealedIndex = -2;
      // New results: open the way to every one of them, so that none is hidden
      // inside a closed branch.
      _tree.reveal(search.matches.map((match) => match.unit >> 1));
    }
    if (search.current < 0) {
      _revealedIndex = -1;
    } else if (_revealedIndex != search.current) {
      _revealedIndex = search.current;
      _revealCurrent();
    }
  }

  void _revealCurrent() {
    final search = widget.search;
    final match = search.matches[search.current];
    final node = match.unit >> 1;
    final model = _tree.model;
    _tree.reveal([node]);
    final value = model.values[node];
    if (match.unit.isOdd &&
        value is String &&
        value.length > jsonStringCut &&
        match.start + search.matchLength > jsonStringCut) {
      // The match is in the part that is cut away, so open the string.
      _tree.setWhole(node, whole: true);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollTo(match);
    });
  }

  void _scrollTo(BodyMatch match) {
    if (!_vertical.hasClients || _nodes.isEmpty) return;
    final node = match.unit >> 1;
    var index = _firstRowOf(node);
    if (index >= _nodes.length || _nodes[index] != node) return;
    if (match.unit.isOdd && _tree.isWhole(node)) {
      final first = _firstChars(node);
      final rest = _restChars(_tree.model.depth[node]);
      final at = match.start + 1; // past the opening quote
      final sub = at < first ? 0 : 1 + (at - first) ~/ rest;
      index += math.min(sub, _extraRows(node));
    }
    final position = _vertical.position;
    final top = _verticalPadding + index * _rowHeight;
    if (top >= position.pixels &&
        top + _rowHeight <= position.pixels + position.viewportDimension) {
      return;
    }
    final target = top - (position.viewportDimension - _rowHeight) / 2;
    _vertical.jumpTo(
      math.min(
        math.max(target, position.minScrollExtent),
        position.maxScrollExtent,
      ),
    );
  }

  void _tap(int node) {
    final model = _tree.model;
    if (model.isContainer(node)) {
      _tree.toggle(node);
    } else {
      final value = model.values[node];
      if (value is String &&
          (value.length > jsonStringCut ||
              value.length + 2 > _firstChars(node))) {
        _tree.toggleWhole(node);
      }
    }
  }

  Future<void> _openMenu(int node, Offset at) async {
    final strings = context.strings;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final choice = await showMenu<_NodeAction>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(at.dx, at.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          value: _NodeAction.copyValue,
          child: Text(strings.copyValue),
        ),
        PopupMenuItem(
          value: _NodeAction.copyPath,
          child: Text(strings.copyPath),
        ),
      ],
    );
    if (!mounted || choice == null) return;
    await _run(node, choice);
  }

  Future<void> _run(int node, _NodeAction action) {
    final model = _tree.model;
    return copyToClipboard(
      context,
      action == _NodeAction.copyValue
          ? model.valueTextOf(node)
          : model.pathOf(node),
    );
  }

  List<InlineSpan> _valueSpans(
    int node,
    int sub,
    FlutwireTokens tokens,
    FlutwireStrings strings,
  ) {
    final model = _tree.model;
    final value = model.values[node];
    if (model.isContainer(node)) {
      final isObject = model.kind(node) == JsonNodeKind.object;
      final count = model.childCount[node];
      final shape = count == 0
          ? (isObject ? '{}' : '[]')
          : _tree.isExpanded(node)
          ? (isObject ? '{' : '[')
          : (isObject ? '{…}' : '[…]');
      return [
        TextSpan(
          text: shape,
          style: TextStyle(color: tokens.syntaxPunctuation),
        ),
        if (count > 0)
          TextSpan(
            text: '  ${strings.itemsCount(count)}',
            style: TextStyle(color: tokens.faint),
          ),
      ];
    }
    if (value is String) {
      final whole = _tree.wholeText(node);
      final text = whole ?? _tree.cutText(node);
      var start = 0;
      var end = text.length;
      if (whole != null) {
        final first = _firstChars(node);
        final rest = _restChars(model.depth[node]);
        if (sub == 0) {
          end = math.min(end, first);
        } else {
          start = first + (sub - 1) * rest;
          end = math.min(end, start + rest);
        }
      }
      return [
        TextSpan(
          style: TextStyle(color: tokens.syntaxString),
          children: styledSpans(
            text: text,
            start: start,
            end: end,
            tokens: tokens,
            // The units hold the text inside the quotes, so shift past the
            // opening one.
            marks: _marksOf(node, value: true, shift: 1),
          ),
        ),
      ];
    }
    final text = model.scalarText(node);
    return [
      TextSpan(
        style: TextStyle(
          color: value is num ? tokens.syntaxNumber : tokens.syntaxKeyword,
        ),
        children: styledSpans(
          text: text,
          start: 0,
          end: text.length,
          tokens: tokens,
          marks: _marksOf(node, value: true),
        ),
      ),
    ];
  }

  Widget _buildRow(
    BuildContext context,
    int index,
    FlutwireTokens tokens,
    FlutwireStrings strings,
  ) {
    final m = metrics;
    final model = _tree.model;
    final node = _nodes[index];
    final sub = _subs[index];
    final depth = model.depth[node];
    final value = model.values[node];
    final hasChildren = model.childCount[node] > 0;
    final spans = <InlineSpan>[];
    if (sub == 0 && node != 0) {
      final key = model.keys[node];
      final label = model.keyLabel(node);
      spans
        ..add(
          TextSpan(
            style: TextStyle(
              color: key is int ? tokens.faint : tokens.syntaxKey,
            ),
            children: key is int
                ? [TextSpan(text: label)]
                : styledSpans(
                    text: label,
                    start: 0,
                    end: label.length,
                    tokens: tokens,
                    marks: _marksOf(node, value: false),
                  ),
          ),
        )
        ..add(
          TextSpan(
            text: ': ',
            style: TextStyle(color: tokens.syntaxPunctuation),
          ),
        );
    }
    spans.addAll(_valueSpans(node, sub, tokens, strings));

    final showControl =
        sub == 0 && value is String && value.length > jsonStringCut;
    final row = Row(
      children: [
        const SizedBox(width: _padLeft),
        SizedBox(
          width: _leading(depth),
          height: _rowHeight,
          child: CustomPaint(
            painter: _GuidePainter(
              depth: depth,
              step: _indentStep,
              box: _chevronBox,
              guide: tokens.line,
              chevron: tokens.muted,
              chevronState: sub == 0 && hasChildren
                  ? (_tree.isExpanded(node) ? _Chevron.open : _Chevron.closed)
                  : _Chevron.none,
            ),
          ),
        ),
        Expanded(
          child: Text.rich(
            TextSpan(children: spans),
            style: m.style,
            strutStyle: m.strut,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            textScaler: TextScaler.noScaling,
          ),
        ),
        if (showControl)
          InkWell(
            onTap: () => _tree.toggleWhole(node),
            child: SizedBox(
              width: _controlWidth,
              height: _rowHeight,
              child: Center(
                child: Text(
                  _tree.isWhole(node) ? strings.showLess : strings.showMore,
                  maxLines: 1,
                  style: tokens.body(
                    size: 11.5,
                    weight: FontWeight.w600,
                    color: tokens.syntaxKey,
                  ),
                ),
              ),
            ),
          ),
        if (_narrow && sub == 0)
          PopupMenuButton<_NodeAction>(
            tooltip: strings.moreActions,
            padding: EdgeInsets.zero,
            onSelected: (action) => _run(node, action),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: _NodeAction.copyValue,
                child: Text(strings.copyValue),
              ),
              PopupMenuItem(
                value: _NodeAction.copyPath,
                child: Text(strings.copyPath),
              ),
            ],
            child: SizedBox(
              width: _menuWidth,
              height: _rowHeight,
              child: Icon(
                Icons.more_horiz_rounded,
                size: 18,
                color: tokens.faint,
              ),
            ),
          )
        else if (_narrow)
          const SizedBox(width: _menuWidth),
        const SizedBox(width: _padRight),
      ],
    );
    return InkWell(
      onTap: () => _tap(node),
      onTapDown: (details) => _lastTap = details.globalPosition,
      onLongPress: () => _openMenu(node, _lastTap),
      onSecondaryTapDown: (details) => _openMenu(node, details.globalPosition),
      child: row,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.fw;
    final strings = context.strings;
    return LayoutBuilder(
      builder: (context, box) {
        _layoutFor(box.maxWidth);
        return ListenableBuilder(
          listenable: widget.search,
          builder: (context, _) {
            _syncMarks();
            return ListView.builder(
              controller: _vertical,
              itemExtent: _rowHeight,
              itemCount: _nodes.length,
              padding: const EdgeInsets.symmetric(vertical: _verticalPadding),
              addAutomaticKeepAlives: false,
              itemBuilder: (context, index) =>
                  _buildRow(context, index, tokens, strings),
            );
          },
        );
      },
    );
  }
}

enum _Chevron { none, closed, open }

/// Draws the guide lines of the levels above a row, and its chevron.
class _GuidePainter extends CustomPainter {
  const _GuidePainter({
    required this.depth,
    required this.step,
    required this.box,
    required this.guide,
    required this.chevron,
    required this.chevronState,
  });

  final int depth;
  final double step;
  final double box;
  final Color guide;
  final Color chevron;
  final _Chevron chevronState;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = guide
      ..strokeWidth = 1;
    for (var d = 0; d < depth; d++) {
      final x = d * step + box / 2;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
    }
    if (chevronState == _Chevron.none) return;
    final cx = depth * step + box / 2;
    final cy = size.height / 2;
    const r = 3.5;
    final path = Path();
    if (chevronState == _Chevron.closed) {
      path
        ..moveTo(cx - r * 0.6, cy - r)
        ..lineTo(cx + r * 0.9, cy)
        ..lineTo(cx - r * 0.6, cy + r);
    } else {
      path
        ..moveTo(cx - r, cy - r * 0.6)
        ..lineTo(cx, cy + r * 0.9)
        ..lineTo(cx + r, cy - r * 0.6);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = chevron);
  }

  @override
  bool shouldRepaint(_GuidePainter old) =>
      old.depth != depth ||
      old.guide != guide ||
      old.chevron != chevron ||
      old.chevronState != chevronState ||
      old.step != step ||
      old.box != box;
}
