import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../actions.dart';
import '../scope.dart';
import '../theme/tokens.dart';
import 'highlight.dart';
import 'json_guides.dart';
import 'json_model.dart';
import 'json_tree_layout.dart';
import 'metrics.dart';
import 'search.dart';
import 'search_follow.dart';

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
  static const double _verticalPadding = 6;

  final ScrollController _vertical = ScrollController();
  late JsonTreeLayout _layout;

  final MatchGroups _marks = MatchGroups((match) => match.unit >> 1);
  final CurrentMatchTracker _tracker = CurrentMatchTracker();
  Offset _lastTap = Offset.zero;

  JsonTreeController get _tree => widget.controller;

  @override
  void initState() {
    super.initState();
    _layout = JsonTreeLayout(_tree);
    _tree.addListener(_onTree);
    widget.search.addListener(_onSearch);
  }

  @override
  void didUpdateWidget(JsonTree oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onTree);
      widget.controller.addListener(_onTree);
      _layout = JsonTreeLayout(widget.controller);
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
    if (!mounted) return;
    setState(_layout.invalidate);
  }

  List<MatchMark> _marksOf(int node, {required bool value, int shift = 0}) =>
      _marks.marks(
        widget.search,
        node,
        where: (match) => match.unit.isOdd == value,
        shift: shift,
      );

  void _onSearch() {
    final search = widget.search;
    if (!identical(search.source, _tree)) return;
    if (_tracker.sawNewResults(search)) {
      // New results: open the way to every one of them, so that none is hidden
      // inside a closed branch.
      _tree.reveal(search.matches.map((match) => match.unit >> 1));
    }
    if (_tracker.arrived(search) != null) _revealCurrent();
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
    if (!_vertical.hasClients || _layout.nodes.isEmpty) return;
    final node = match.unit >> 1;
    var index = _layout.firstRowOf(node);
    if (index >= _layout.nodes.length || _layout.nodes[index] != node) return;
    if (match.unit.isOdd && _tree.isWhole(node)) {
      final first = _layout.firstChars(node);
      final rest = _layout.restChars(_tree.model.depth[node]);
      final at = match.start + 1; // past the opening quote
      final sub = at < first ? 0 : 1 + (at - first) ~/ rest;
      index += math.min(sub, _layout.extraRows(node));
    }
    final position = _vertical.position;
    final top = _verticalPadding + index * _layout.rowHeight;
    if (top >= position.pixels &&
        top + _layout.rowHeight <=
            position.pixels + position.viewportDimension) {
      return;
    }
    final target = top - (position.viewportDimension - _layout.rowHeight) / 2;
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
              value.length + 2 > _layout.firstChars(node))) {
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
    return copyText(
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
        final first = _layout.firstChars(node);
        final rest = _layout.restChars(model.depth[node]);
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
    final node = _layout.nodes[index];
    final sub = _layout.subs[index];
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
        const SizedBox(width: JsonTreeLayout.padLeft),
        SizedBox(
          width: JsonTreeLayout.leading(depth),
          height: _layout.rowHeight,
          child: CustomPaint(
            painter: GuidePainter(
              depth: depth,
              step: JsonTreeLayout.indentStep,
              box: JsonTreeLayout.chevronBox,
              guide: tokens.line,
              chevron: tokens.muted,
              chevronState: sub == 0 && hasChildren
                  ? (_tree.isExpanded(node) ? Chevron.open : Chevron.closed)
                  : Chevron.none,
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
              width: JsonTreeLayout.controlWidth,
              height: _layout.rowHeight,
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
        if (_layout.narrow && sub == 0)
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
              width: JsonTreeLayout.menuWidth,
              height: _layout.rowHeight,
              child: Icon(
                Icons.more_horiz_rounded,
                size: 18,
                color: tokens.faint,
              ),
            ),
          )
        else if (_layout.narrow)
          const SizedBox(width: JsonTreeLayout.menuWidth),
        const SizedBox(width: JsonTreeLayout.padRight),
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
        _layout.update(box.maxWidth, metrics);
        return ListenableBuilder(
          listenable: widget.search,
          builder: (context, _) {
            _marks.sync(widget.search.matches);
            return ListView.builder(
              controller: _vertical,
              itemExtent: _layout.rowHeight,
              itemCount: _layout.nodes.length,
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
