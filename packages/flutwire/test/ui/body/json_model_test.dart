import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/src/ui/body/json_model.dart';

JsonTreeModel modelOf(String json) =>
    JsonTreeModel.build(jsonDecode(json) as Object?);

JsonTreeController treeOf(String json) =>
    JsonTreeController(jsonDecode(json) as Object?);

void main() {
  group('the model', () {
    test('knows each node from its parent, depth and end', () {
      final model = modelOf('{"a":{"b":[1,{"c":"x"}]},"d":null}');

      // 0 root, 1 a, 2 b, 3 b[0], 4 b[1], 5 c, 6 d
      expect(model.length, 7);
      expect(model.parent, [-1, 0, 1, 2, 2, 4, 0]);
      expect(model.depth, [0, 1, 2, 3, 3, 4, 1]);
      expect(model.end, [7, 6, 6, 4, 6, 6, 7]);
      expect(model.childCount, [2, 1, 2, 0, 1, 0, 0]);
    });

    test('tells containers from scalars', () {
      final model = modelOf('{"a":[1],"b":"s","c":2}');

      expect(model.kind(0), JsonNodeKind.object);
      expect(model.kind(1), JsonNodeKind.array);
      expect(model.kind(2), JsonNodeKind.scalar);
      expect(model.isContainer(0), isTrue);
      expect(model.isContainer(3), isFalse);
      expect(model.isString(3), isTrue);
      expect(model.isString(4), isFalse);
    });

    test('is one node for a document that is a scalar', () {
      expect(modelOf('42').length, 1);
      expect(modelOf('"s"').length, 1);
      expect(modelOf('null').length, 1);
    });

    test('is one node for an empty container', () {
      expect(modelOf('{}').length, 1);
      expect(modelOf('[]').length, 1);
    });

    test('flattens a very deep document without overflowing the stack', () {
      Object? deep = 1;
      for (var i = 0; i < 50000; i++) {
        deep = [deep];
      }

      final model = JsonTreeModel.build(deep);

      expect(model.length, 50001);
      expect(model.depth.last, 50000);
    });
  });

  group('how a key is shown', () {
    test('as the key for an object member and the index for an array', () {
      final model = modelOf('{"a":[10]}');

      expect(model.keyLabel(1), 'a');
      expect(model.keyLabel(2), '0');
    });

    test('with control characters turned into spaces', () {
      final model = modelOf('{"two\\nlines":1}');

      expect(model.keyLabel(1), 'two lines');
    });

    test('cut when it is very long', () {
      final model = modelOf('{"${'k' * 500}":1}');

      final label = model.keyLabel(1);

      expect(label.length, jsonKeyCut + 1);
      expect(label, endsWith('…'));
    });
  });

  group('the path of a node', () {
    test('is written as JSONPath', () {
      final model = modelOf('{"items":[{"name":"x"}]}');

      expect(model.pathOf(0), r'$');
      expect(model.pathOf(3), r'$.items[0].name');
    });

    test('puts a key that is not an identifier in brackets', () {
      final model = modelOf('{"key with space":{"it\'s":1}}');

      expect(model.pathOf(2), r"$['key with space']['it\'s']");
    });

    test('escapes a backslash in a key', () {
      final model = modelOf('{"a\\\\b":1}');

      expect(model.pathOf(1), r"$['a\\b']");
    });
  });

  group('what copying a value gives', () {
    test('a string without its quotes', () {
      expect(modelOf('{"a":"hi"}').valueTextOf(1), 'hi');
    });

    test('a scalar as it reads', () {
      final model = modelOf('{"n":1.5,"b":true,"z":null}');

      expect(model.valueTextOf(1), '1.5');
      expect(model.valueTextOf(2), 'true');
      expect(model.valueTextOf(3), 'null');
      expect(model.scalarText(1), '1.5');
    });

    test('a container as indented JSON', () {
      expect(modelOf('{"a":[1]}').valueTextOf(1), '[\n  1\n]');
    });
  });

  group('escapeJsonText', () {
    test('hands back text that needs nothing', () {
      const text = 'plain text';

      expect(identical(escapeJsonText(text), text), isTrue);
    });

    test('escapes quotes, backslashes and line breaks', () {
      expect(escapeJsonText('say "hi"\\\n\r\t'), r'say \"hi\"\\\n\r\t');
    });

    test('escapes the other control characters', () {
      expect(escapeJsonText('\u0008\u000C\u0001'), r'\b\f\u0001');
    });
  });

  group('the controller', () {
    test('opens the root, and its children when there are few', () {
      final tree = treeOf('{"a":{"x":1},"b":[2]}');

      expect(tree.isExpanded(0), isTrue);
      expect(tree.isExpanded(1), isTrue);
      expect(tree.isExpanded(3), isTrue);
    });

    test('opens only the root when it has many children', () {
      final many = {
        for (var i = 0; i < JsonTreeController.openChildrenLimit + 1; i++)
          'k$i': [i],
      };
      final tree = JsonTreeController(many);

      expect(tree.isExpanded(0), isTrue);
      expect(tree.isExpanded(1), isFalse);
    });

    test('toggles a container and tells its listeners', () {
      final tree = treeOf('{"a":[1]}');
      var heard = 0;
      tree.addListener(() => heard++);
      final before = tree.version;

      tree.toggle(1);

      expect(tree.isExpanded(1), isFalse);
      expect(heard, 1);
      expect(tree.version, before + 1);
    });

    test('leaves scalars and empty containers alone', () {
      final tree = treeOf('{"a":1,"b":[]}');
      var heard = 0;
      tree.addListener(() => heard++);

      tree
        ..toggle(1)
        ..toggle(2);

      expect(heard, 0);
    });

    test('expands everything, and collapses all but the root', () {
      final tree = treeOf('{"a":{"b":{"c":[1]}}}')..collapseAll();
      expect(tree.isExpanded(0), isTrue);
      expect(tree.isExpanded(1), isFalse);

      tree.expandAll();

      expect(
        [for (var i = 0; i < 5; i++) tree.isExpanded(i)],
        [true, true, true, true, false],
      );
    });

    test('reveals a node by opening everything above it', () {
      final tree = treeOf('{"a":{"b":{"c":1}}}')..collapseAll();

      final opened = tree.reveal([3]);

      expect(opened, isTrue);
      expect(tree.isExpanded(1), isTrue);
      expect(tree.isExpanded(2), isTrue);
      expect(tree.reveal([3]), isFalse);
    });
  });

  group('a string shown in full', () {
    final long = 'a"b' * 100;

    test('is cut at the limit until it is opened', () {
      final tree = treeOf('{"s":${jsonEncode(long)}}');

      final cut = tree.cutText(1);

      expect(cut.startsWith('"'), isTrue);
      expect(cut.endsWith('…'), isTrue);
      expect(tree.isWhole(1), isFalse);
      expect(tree.wholeText(1), isNull);
    });

    test('keeps a short string whole, quoted and escaped', () {
      final tree = treeOf('{"s":"a\\"b"}');

      expect(tree.cutText(1), r'"a\"b"');
    });

    test('is quoted and escaped in full once opened', () {
      final tree = treeOf('{"s":${jsonEncode(long)}}')..toggleWhole(1);

      expect(tree.isWhole(1), isTrue);
      expect(tree.wholeText(1), '"${escapeJsonText(long)}"');
    });

    test('closes again when toggled twice', () {
      final tree = treeOf('{"s":${jsonEncode(long)}}')
        ..toggleWhole(1)
        ..toggleWhole(1);

      expect(tree.isWhole(1), isFalse);
    });

    test('is only for strings', () {
      final tree = treeOf('{"n":1}')..toggleWhole(1);

      expect(tree.isWhole(1), isFalse);
    });

    test('is not cut in the middle of a surrogate pair', () {
      final text = '${'a' * (jsonStringCut - 1)}😀tail';
      final tree = treeOf('{"s":${jsonEncode(text)}}');

      final cut = tree.cutText(1);

      expect(cut.codeUnits.contains(0xD83D), isFalse);
    });

    test('takes the rows its length asks for', () {
      expect(JsonTreeController.rowsFor(10, first: 20, rest: 30), 1);
      expect(JsonTreeController.rowsFor(50, first: 20, rest: 30), 2);
      expect(JsonTreeController.rowsFor(51, first: 20, rest: 30), 3);
    });
  });

  group('the units a search runs through', () {
    test('are the keys of objects and the values of scalars', () {
      final tree = treeOf('{"name":"Ada","tags":["x"],"n":3}');
      final seen = <int, String>{};

      tree.forEachUnit((unit, text) {
        seen[unit] = text;
        return true;
      });

      expect(seen, {2: 'name', 3: 'Ada', 4: 'tags', 7: 'x', 8: 'n', 9: '3'});
    });

    test('stop when asked to', () {
      final tree = treeOf('{"a":1,"b":2}');
      var visited = 0;

      tree.forEachUnit((unit, text) {
        visited++;
        return false;
      });

      expect(visited, 1);
    });
  });
}
