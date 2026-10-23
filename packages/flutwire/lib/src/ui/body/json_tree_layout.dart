import 'dart:math' as math;
import 'dart:typed_data';

import 'json_model.dart';
import 'metrics.dart';

/// Which node each row of a JSON tree shows, at a given width.
///
/// Every row is the same height. A node is one row, except a string opened in
/// full, which takes as many rows as its characters need at this width, so the
/// tree is a plain list over [nodes] and [subs]. Row `r` shows node `nodes[r]`,
/// and `subs[r]` is 0 for the node's first row and counts up for the rows of an
/// opened string after it.
///
/// The layout holds no widgets. It is worked out again when the tree opens or
/// closes something, when the width or the narrow layout changes, and when the
/// width of a character does, which happens when a font finishes loading.
final class JsonTreeLayout {
  /// Creates a layout for the nodes of [tree].
  JsonTreeLayout(this.tree);

  /// How far each level of depth is indented.
  static const double indentStep = 14;

  /// The width of the box that holds the chevron.
  static const double chevronBox = 18;

  /// The space before the guides of a row.
  static const double padLeft = 8;

  /// The space after the text of a row.
  static const double padRight = 4;

  /// The width of the menu button a narrow layout puts on each row.
  static const double menuWidth = 40;

  /// The width of the "show more" control of a long string.
  static const double controlWidth = 84;

  /// The fewest characters a row of an opened string is allowed to hold.
  static const int minChars = 8;

  /// The tree whose nodes are listed.
  final JsonTreeController tree;

  /// The node each row shows.
  Int32List nodes = Int32List(0);

  /// Which row of its node each row is.
  Int32List subs = Int32List(0);

  /// The width the layout was worked out for.
  double width = -1;

  /// Whether the narrow layout is in force.
  bool narrow = false;

  /// The height of a row, in logical pixels.
  double rowHeight = 28;

  bool _stale = true;
  double _charWidth = 0;
  BodyMetrics? _metrics;

  /// Makes the next [update] work the rows out again, because the tree opened
  /// or closed something.
  void invalidate() => _stale = true;

  /// Works the rows out again if something they depend on changed since the
  /// last call. [width] is what the rows may use, and [metrics] measures the
  /// characters.
  void update(double width, BodyMetrics metrics) {
    final isNarrow = width < bodyNarrowWidth;
    final changed =
        _stale ||
        width != this.width ||
        isNarrow != narrow ||
        metrics.charWidth != _charWidth;
    this.width = width;
    narrow = isNarrow;
    _charWidth = metrics.charWidth;
    _metrics = metrics;
    rowHeight = ((isNarrow ? 40 : 28) * metrics.lineHeight / bodyLineHeight)
        .roundToDouble();
    if (!changed) return;
    _stale = false;
    final model = tree.model;
    final nodeList = <int>[];
    final subList = <int>[];
    var i = 0;
    while (i < model.length) {
      nodeList.add(i);
      subList.add(0);
      if (!model.isContainer(i)) {
        final extra = extraRows(i);
        for (var k = 1; k <= extra; k++) {
          nodeList.add(i);
          subList.add(k);
        }
        i++;
      } else if (tree.isExpanded(i)) {
        i++;
      } else {
        i = model.end[i];
      }
    }
    nodes = Int32List.fromList(nodeList);
    subs = Int32List.fromList(subList);
  }

  /// The width of the guides and the chevron before a node at [depth].
  static double leading(int depth) => depth * indentStep + chevronBox;

  /// How many characters fit on each row after the first of an opened string.
  int restChars(int depth) => math.max(
    minChars,
    _metrics!.cellsIn(width - padLeft - leading(depth) - padRight),
  );

  /// How many characters of an opened string fit on its first row, which also
  /// holds the key and, on a phone, the menu button.
  int firstChars(int node) {
    final model = tree.model;
    var room = width - padLeft - leading(model.depth[node]) - padRight;
    if (narrow) room -= menuWidth;
    final value = model.values[node];
    if (value is String && value.length > jsonStringCut) {
      room -= controlWidth;
    }
    final prefix = node == 0 ? 0 : model.keyLabel(node).length + 2;
    return math.max(minChars, _metrics!.cellsIn(room) - prefix);
  }

  /// How many rows after its first the string at [node] takes, which is none
  /// unless it is opened in full.
  int extraRows(int node) {
    final whole = tree.wholeText(node);
    if (whole == null) return 0;
    return JsonTreeController.rowsFor(
          whole.length,
          first: firstChars(node),
          rest: restChars(tree.model.depth[node]),
        ) -
        1;
  }

  /// The index of the first row that shows [node], or where it would be.
  int firstRowOf(int node) {
    var lo = 0;
    var hi = nodes.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (nodes[mid] < node) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }
}
