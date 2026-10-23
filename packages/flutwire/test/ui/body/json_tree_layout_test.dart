import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/src/ui/body/json_model.dart';
import 'package:flutwire/src/ui/body/json_tree_layout.dart';
import 'package:flutwire/src/ui/body/metrics.dart';
import 'package:flutwire/src/ui/theme/tokens.dart';

JsonTreeController treeOf(String json) =>
    JsonTreeController(jsonDecode(json) as Object?);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final metrics = BodyMetrics.resolve(
    FlutwireTokens.dark,
    TextScaler.noScaling,
  );

  JsonTreeLayout layoutOf(JsonTreeController tree, {double width = 800}) =>
      JsonTreeLayout(tree)..update(width, metrics);

  group('the rows', () {
    test('are one per node while everything is open', () {
      final layout = layoutOf(treeOf('{"a":1,"b":[1,2]}'));

      expect(layout.nodes, [0, 1, 2, 3, 4]);
      expect(layout.subs, [0, 0, 0, 0, 0]);
    });

    test('skip the inside of a closed branch', () {
      final tree = treeOf('{"a":1,"b":[1,2],"c":3}');
      final layout = layoutOf(tree);
      expect(layout.nodes, [0, 1, 2, 3, 4, 5]);

      tree.toggle(2);
      layout
        ..invalidate()
        ..update(800, metrics);

      expect(layout.nodes, [0, 1, 2, 5]);
    });

    test('are only the root for a document that is a scalar', () {
      final layout = layoutOf(treeOf('"hello"'));

      expect(layout.nodes, [0]);
    });

    test('are left alone when nothing they depend on changed', () {
      final layout = layoutOf(treeOf('{"a":1}'));
      final before = layout.nodes;

      layout.update(800, metrics);

      expect(identical(layout.nodes, before), isTrue);
    });

    test('are worked out again when the width changes', () {
      final tree = treeOf('{"a":"${'x' * 500}"}')..setWhole(1, whole: true);
      final layout = layoutOf(tree);
      final wide = layout.nodes.length;

      layout.update(300, metrics);

      expect(layout.nodes.length, greaterThan(wide));
    });
  });

  group('a string opened in full', () {
    test('takes as many rows as its characters need', () {
      final tree = treeOf('{"a":"${'x' * 500}"}')..setWhole(1, whole: true);
      final layout = layoutOf(tree);

      final rows = layout.nodes.where((node) => node == 1).length;

      expect(rows, 1 + layout.extraRows(1));
      expect(rows, greaterThan(1));
      final subs = [
        for (var i = 0; i < layout.nodes.length; i++)
          if (layout.nodes[i] == 1) layout.subs[i],
      ];
      expect(subs, [for (var k = 0; k < rows; k++) k]);
    });

    test('is one row while it is cut', () {
      final layout = layoutOf(treeOf('{"a":"${'x' * 500}"}'));

      expect(layout.extraRows(1), 0);
      expect(layout.nodes.where((node) => node == 1), hasLength(1));
    });

    test('fits more characters on a wide row than on a narrow one', () {
      final tree = treeOf('{"a":"${'x' * 500}"}');
      final wide = layoutOf(tree);
      final narrow = layoutOf(tree, width: 320);

      expect(wide.restChars(1), greaterThan(narrow.restChars(1)));
      expect(wide.firstChars(1), greaterThan(narrow.firstChars(1)));
    });

    test('never fits fewer characters than the minimum', () {
      final layout = layoutOf(treeOf('{"a":"${'x' * 500}"}'), width: 40);

      expect(layout.restChars(1), JsonTreeLayout.minChars);
      expect(layout.firstChars(1), JsonTreeLayout.minChars);
    });

    test('gives up room on the first row for the key', () {
      final tree = treeOf('{"a":"${'x' * 500}","a long key":"${'x' * 500}"}');
      final layout = layoutOf(tree);

      expect(layout.firstChars(1), greaterThan(layout.firstChars(2)));
    });
  });

  group('the shape of the layout', () {
    test('is wide above the phone width and narrow below it', () {
      final tree = treeOf('{"a":1}');

      final wide = layoutOf(tree, width: bodyNarrowWidth);
      final narrow = layoutOf(tree, width: bodyNarrowWidth - 1);

      expect(wide.narrow, isFalse);
      expect(narrow.narrow, isTrue);
      expect(narrow.rowHeight, greaterThan(wide.rowHeight));
    });

    test('indents a level by a fixed step', () {
      expect(
        JsonTreeLayout.leading(3) - JsonTreeLayout.leading(2),
        JsonTreeLayout.indentStep,
      );
    });
  });

  group('finding a node', () {
    test('gives the first row that shows it', () {
      final layout = layoutOf(treeOf('{"a":1,"b":2,"c":3}'));

      expect(layout.firstRowOf(0), 0);
      expect(layout.firstRowOf(3), 3);
    });

    test('gives the first of several rows of an opened string', () {
      final tree = treeOf('{"a":"${'x' * 500}","b":2}')
        ..setWhole(1, whole: true);
      final layout = layoutOf(tree);

      expect(layout.firstRowOf(1), 1);
      expect(layout.nodes[layout.firstRowOf(2)], 2);
      expect(layout.firstRowOf(2), greaterThan(2));
    });

    test('gives the place it would be when it is hidden', () {
      final tree = treeOf('{"a":[1,2],"b":3}')..toggle(1);
      final layout = layoutOf(tree);

      expect(layout.nodes, [0, 1, 4]);
      expect(layout.nodes[layout.firstRowOf(2)], isNot(2));
    });
  });
}
