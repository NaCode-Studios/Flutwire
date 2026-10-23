import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'search.dart';

/// How many characters of a string the tree shows before it cuts the string
/// and offers to show the rest.
const int jsonStringCut = 160;

/// The most characters of an object key the tree shows.
const int jsonKeyCut = 400;

/// What a node of the tree holds.
enum JsonNodeKind {
  /// A string, number, boolean or null.
  scalar,

  /// An object.
  object,

  /// An array.
  array,
}

class _Frame {
  _Frame(this.node, this.entries, this.list);

  final int node;
  final Iterator<MapEntry<Object?, Object?>>? entries;
  final List<Object?>? list;
  int next = 0;
}

/// A parsed JSON document, flattened into nodes in document order.
///
/// Node `i` has its subtree in `[i, end[i])`, so skipping a closed branch is a
/// single assignment and the rows on screen can be listed without visiting the
/// rest. The flattening uses a stack of its own rather than recursion, so
/// nesting a hundred thousand levels deep costs memory and never a stack
/// overflow.
final class JsonTreeModel {
  JsonTreeModel._(
    this.parent,
    this.depth,
    this.end,
    this.childCount,
    this._kind,
    this.keys,
    this.values,
  );

  /// Flattens [root], which is a value as `jsonDecode` returns it.
  factory JsonTreeModel.build(Object? root) {
    final parents = <int>[];
    final depths = <int>[];
    final ends = <int>[];
    final counts = <int>[];
    final kinds = <int>[];
    final keys = <Object?>[];
    final values = <Object?>[];

    int add(int parent, int depth, Object? key, Object? value) {
      final index = parents.length;
      parents.add(parent);
      depths.add(depth);
      ends.add(index + 1);
      if (value is Map) {
        kinds.add(JsonNodeKind.object.index);
        counts.add(value.length);
      } else if (value is List) {
        kinds.add(JsonNodeKind.array.index);
        counts.add(value.length);
      } else {
        kinds.add(JsonNodeKind.scalar.index);
        counts.add(0);
      }
      keys.add(key);
      values.add(value);
      return index;
    }

    _Frame? frameFor(int node, Object? value) {
      if (value is Map && value.isNotEmpty) {
        return _Frame(node, value.entries.iterator, null);
      }
      if (value is List && value.isNotEmpty) {
        return _Frame(node, null, value);
      }
      return null;
    }

    final stack = <_Frame>[];
    final rootFrame = frameFor(add(-1, 0, null, root), root);
    if (rootFrame != null) stack.add(rootFrame);
    while (stack.isNotEmpty) {
      final frame = stack.last;
      Object? key;
      Object? value;
      var has = false;
      final entries = frame.entries;
      if (entries != null) {
        has = entries.moveNext();
        if (has) {
          key = entries.current.key;
          value = entries.current.value;
        }
      } else {
        final list = frame.list!;
        has = frame.next < list.length;
        if (has) {
          key = frame.next;
          value = list[frame.next++];
        }
      }
      if (!has) {
        ends[frame.node] = parents.length;
        stack.removeLast();
        continue;
      }
      final index = add(
        frame.node,
        depths[frame.node] + 1,
        key is int ? key : '$key',
        value,
      );
      final child = frameFor(index, value);
      if (child != null) stack.add(child);
    }
    return JsonTreeModel._(
      Int32List.fromList(parents),
      Int32List.fromList(depths),
      Int32List.fromList(ends),
      Int32List.fromList(counts),
      Uint8List.fromList(kinds),
      keys,
      values,
    );
  }

  /// The index of each node's parent, or -1 for the root.
  final Int32List parent;

  /// How deep each node is; the root is 0.
  final Int32List depth;

  /// The index after the last node of each node's subtree.
  final Int32List end;

  /// How many children each node has.
  final Int32List childCount;

  final Uint8List _kind;

  /// The key of each node: a string for an object member, an int for an array
  /// element, null for the root.
  final List<Object?> keys;

  /// The value of each node, as decoded.
  final List<Object?> values;

  /// The number of nodes.
  int get length => parent.length;

  /// What node [i] holds.
  JsonNodeKind kind(int i) => JsonNodeKind.values[_kind[i]];

  /// Whether node [i] is an object or an array.
  bool isContainer(int i) => _kind[i] != JsonNodeKind.scalar.index;

  /// Whether node [i] is a string.
  bool isString(int i) => values[i] is String;

  /// The key of node [i] as it is shown: control characters become spaces,
  /// because a row is one line, and a very long key is cut.
  String keyLabel(int i) {
    final key = keys[i];
    if (key is! String) return '$key';
    var out = key.length > jsonKeyCut
        ? '${key.substring(0, jsonKeyCut)}…'
        : key;
    if (out.codeUnits.any((c) => c < 0x20)) {
      out = String.fromCharCodes([
        for (final c in out.codeUnits) c < 0x20 ? 0x20 : c,
      ]);
    }
    return out;
  }

  /// The text of a scalar that is not a string, as it is shown.
  String scalarText(int i) => '${values[i]}';

  static final RegExp _identifier = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

  /// The JSONPath of node [i], such as `$.items[0].name`. A key that is not a
  /// plain identifier is written in brackets, `$['key with space']`.
  String pathOf(int i) {
    final segments = <String>[];
    var node = i;
    while (node > 0) {
      final key = keys[node];
      if (key is int) {
        segments.add('[$key]');
      } else {
        final name = key! as String;
        segments.add(
          _identifier.hasMatch(name)
              ? '.$name'
              : "['${name.replaceAll(r'\', r'\\').replaceAll("'", r"\'")}']",
        );
      }
      node = parent[node];
    }
    return '\$${segments.reversed.join()}';
  }

  /// What copying the value of node [i] puts on the clipboard: a scalar as its
  /// plain value, a string without its quotes, a container as indented JSON.
  String valueTextOf(int i) {
    final value = values[i];
    if (value is String) return value;
    if (value is Map || value is List) {
      try {
        return const JsonEncoder.withIndent('  ').convert(value);
      } on Object {
        // Nesting deeper than the encoder can follow. The summary is the most
        // that can honestly be offered.
        return value is Map ? '{…}' : '[…]';
      }
    }
    return '$value';
  }
}

/// Escapes [text] the way a JSON string is written, minus the quotes, so that
/// a string with a line break still fits on one row.
String escapeJsonText(String text) {
  var clean = true;
  for (var i = 0; i < text.length; i++) {
    final c = text.codeUnitAt(i);
    if (c < 0x20 || c == 0x22 || c == 0x5C) {
      clean = false;
      break;
    }
  }
  if (clean) return text;
  final out = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    final c = text.codeUnitAt(i);
    switch (c) {
      case 0x22:
        out.write(r'\"');
      case 0x5C:
        out.write(r'\\');
      case 0x0A:
        out.write(r'\n');
      case 0x0D:
        out.write(r'\r');
      case 0x09:
        out.write(r'\t');
      case 0x08:
        out.write(r'\b');
      case 0x0C:
        out.write(r'\f');
      default:
        if (c < 0x20) {
          out.write('\\u${c.toRadixString(16).padLeft(4, '0')}');
        } else {
          out.writeCharCode(c);
        }
    }
  }
  return out.toString();
}

/// The open and closed state of a [JsonTreeModel], and the search units of its
/// text.
///
/// It is separate from the widget so that it outlives it: switching to another
/// mode and back finds the tree as it was left.
final class JsonTreeController extends ChangeNotifier
    implements BodySearchSource {
  /// Flattens [root] and opens it the way a first look wants: the root, and its
  /// children too when it has at most [openChildrenLimit] of them.
  JsonTreeController(Object? root) : this._(JsonTreeModel.build(root));

  JsonTreeController._(this.model) : _expanded = Uint8List(model.length) {
    if (model.length == 0 || model.childCount[0] == 0) return;
    _expanded[0] = 1;
    if (model.childCount[0] <= openChildrenLimit) {
      for (var i = 1; i < model.end[0]; i = model.end[i]) {
        if (model.isContainer(i)) _expanded[i] = 1;
      }
    }
  }

  /// The most children a root may have for its children to start open.
  static const int openChildrenLimit = 20;

  /// The document.
  final JsonTreeModel model;

  final Uint8List _expanded;
  final Map<int, String> _whole = {};

  /// Changes every time the set of rows can have changed.
  int get version => _version;
  int _version = 0;

  /// Whether container [node] shows its children.
  bool isExpanded(int node) => _expanded[node] != 0;

  /// Whether string [node] is shown in full rather than cut.
  bool isWhole(int node) => _whole.containsKey(node);

  /// Opens or closes container [node].
  void toggle(int node) {
    if (!model.isContainer(node) || model.childCount[node] == 0) return;
    _expanded[node] = _expanded[node] == 0 ? 1 : 0;
    _changed();
  }

  /// Shows string [node] in full, or cuts it again.
  void toggleWhole(int node) {
    if (!model.isString(node)) return;
    setWhole(node, whole: !isWhole(node));
  }

  /// Shows string [node] in full when [whole] is true, and cuts it when false.
  void setWhole(int node, {required bool whole}) {
    if (whole == isWhole(node) || !model.isString(node)) return;
    if (whole) {
      _whole[node] = '"${escapeJsonText(model.values[node]! as String)}"';
    } else {
      _whole.remove(node);
    }
    _changed();
  }

  /// Opens every container.
  void expandAll() {
    for (var i = 0; i < model.length; i++) {
      if (model.childCount[i] > 0) _expanded[i] = 1;
    }
    _changed();
  }

  /// Closes every container below the root, which stays open so that the
  /// first level is still in view.
  void collapseAll() {
    _expanded.fillRange(0, _expanded.length, 0);
    if (model.length > 0 && model.childCount[0] > 0) _expanded[0] = 1;
    _changed();
  }

  /// Opens every ancestor of [nodes], so that they can all be seen. Returns
  /// whether anything had to be opened.
  bool reveal(Iterable<int> nodes) {
    var opened = false;
    for (final node in nodes) {
      for (var p = model.parent[node]; p >= 0; p = model.parent[p]) {
        if (_expanded[p] == 0) {
          _expanded[p] = 1;
          opened = true;
        }
      }
    }
    if (opened) _changed();
    return opened;
  }

  /// The quoted, escaped text of string [node] while it is shown in full.
  String? wholeText(int node) => _whole[node];

  /// The quoted text of string [node] as it is shown cut: at most
  /// [jsonStringCut] characters of it, then an ellipsis.
  String cutText(int node) {
    final value = model.values[node]! as String;
    if (value.length <= jsonStringCut) {
      return '"${escapeJsonText(value)}"';
    }
    var end = jsonStringCut;
    // Do not cut a surrogate pair in half.
    if (value.codeUnitAt(end) >= 0xDC00 && value.codeUnitAt(end) <= 0xDFFF) {
      end--;
    }
    return '"${escapeJsonText(value.substring(0, end))}…';
  }

  void _changed() {
    _version++;
    notifyListeners();
  }

  /// Unit `2 * node` is the key of a node and `2 * node + 1` its value, when
  /// it is a scalar. Array indices are not searched: they are labels, not data.
  @override
  void forEachUnit(bool Function(int unit, String text) visit) {
    for (var i = 0; i < model.length; i++) {
      if (model.keys[i] is String && !visit(i * 2, model.keyLabel(i))) return;
      if (!model.isContainer(i)) {
        final value = model.values[i];
        final text = value is String ? escapeJsonText(value) : '$value';
        if (!visit(i * 2 + 1, text)) return;
      }
    }
  }

  /// The number of rows a string needs when shown in full, given how many
  /// characters fit on its first row and on each row after it.
  static int rowsFor(int length, {required int first, required int rest}) =>
      1 + math.max(0, (length - first + rest - 1) ~/ math.max(1, rest));
}
