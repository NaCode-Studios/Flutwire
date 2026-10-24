import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/src/compare/diff.dart';

List<String> _lines(String text) => text.isEmpty ? [] : text.split('\n');

/// The left side of [rows], as the comparison read it.
List<String> _lefts(List<DiffRow> rows) => [
  for (final row in rows)
    if (row.left != null) row.left!,
];

List<String> _rights(List<DiffRow> rows) => [
  for (final row in rows)
    if (row.right != null) row.right!,
];

List<DiffKind> _kinds(List<DiffRow> rows) => [for (final r in rows) r.kind];

/// The number of lines the two sides share, in order, by the long way.
int _commonLines(List<String> a, List<String> b) {
  final table = List.generate(
    a.length + 1,
    (_) => List.filled(b.length + 1, 0),
  );
  for (var i = 1; i <= a.length; i++) {
    for (var j = 1; j <= b.length; j++) {
      table[i][j] = a[i - 1] == b[j - 1]
          ? table[i - 1][j - 1] + 1
          : max(table[i - 1][j], table[i][j - 1]);
    }
  }
  return table[a.length][b.length];
}

void main() {
  group('diffLines', () {
    test('finds nothing in two equal texts', () {
      final rows = diffLines(_lines('a\nb\nc'), _lines('a\nb\nc'));

      expect(_kinds(rows), [DiffKind.same, DiffKind.same, DiffKind.same]);
    });

    test('pairs a line that changed', () {
      final rows = diffLines(_lines('a\nb\nc'), _lines('a\nB\nc'));

      expect(_kinds(rows), [DiffKind.same, DiffKind.changed, DiffKind.same]);
      expect(rows[1].left, 'b');
      expect(rows[1].right, 'B');
    });

    test('finds a line that was added', () {
      final rows = diffLines(_lines('a\nc'), _lines('a\nb\nc'));

      expect(_kinds(rows), [DiffKind.same, DiffKind.onlyRight, DiffKind.same]);
      expect(rows[1].right, 'b');
      expect(rows[1].left, isNull);
    });

    test('finds a line that was removed', () {
      final rows = diffLines(_lines('a\nb\nc'), _lines('a\nc'));

      expect(_kinds(rows), [DiffKind.same, DiffKind.onlyLeft, DiffKind.same]);
      expect(rows[1].left, 'b');
    });

    test('pairs what was replaced and leaves the rest alone', () {
      final rows = diffLines(
        _lines('start\nx\ny\nend'),
        _lines('start\n1\n2\n3\nend'),
      );

      expect(_kinds(rows), [
        DiffKind.same,
        DiffKind.changed,
        DiffKind.changed,
        DiffKind.onlyRight,
        DiffKind.same,
      ]);
      expect(rows[3].right, '3');
    });

    test('reads an empty side as everything added or removed', () {
      expect(_kinds(diffLines(const [], _lines('a\nb'))), [
        DiffKind.onlyRight,
        DiffKind.onlyRight,
      ]);
      expect(_kinds(diffLines(_lines('a\nb'), const [])), [
        DiffKind.onlyLeft,
        DiffKind.onlyLeft,
      ]);
      expect(diffLines(const [], const []), isEmpty);
    });

    test('does not mistake a repeated line for a moved one', () {
      final rows = diffLines(_lines('a\na\nb'), _lines('a\nb\nb'));

      expect(_lefts(rows), ['a', 'a', 'b']);
      expect(_rights(rows), ['a', 'b', 'b']);
      expect(rows.where((r) => r.kind == DiffKind.same), hasLength(2));
    });

    test('puts back both sides exactly, and shares as much as it can', () {
      final random = Random(7);
      for (var round = 0; round < 300; round++) {
        final a = [
          for (var i = 0; i < random.nextInt(12); i++)
            'ab c'[random.nextInt(4)],
        ];
        final b = [
          for (var i = 0; i < random.nextInt(12); i++)
            'ab c'[random.nextInt(4)],
        ];

        final rows = diffLines(a, b);

        expect(_lefts(rows), a, reason: '$a against $b');
        expect(_rights(rows), b, reason: '$a against $b');
        for (final row in rows.where((r) => r.kind == DiffKind.same)) {
          expect(row.left, row.right);
        }
        expect(
          rows.where((r) => r.kind == DiffKind.same),
          hasLength(_commonLines(a, b)),
          reason: '$a against $b',
        );
      }
    });

    test('still puts both sides back when the texts have little in common', () {
      final a = [for (var i = 0; i < 60; i++) 'left $i'];
      final b = [for (var i = 0; i < 80; i++) 'right $i'];

      final rows = diffLines(a, b, maxEdits: 5);

      expect(_lefts(rows), a);
      expect(_rights(rows), b);
      expect(rows.where((r) => r.kind == DiffKind.changed), hasLength(60));
      expect(rows.where((r) => r.kind == DiffKind.onlyRight), hasLength(20));
    });

    test('copes with a long text that changed in a few places', () {
      final a = [for (var i = 0; i < 6000; i++) 'line $i'];
      final b = [...a]
        ..[10] = 'ten'
        ..removeAt(3000)
        ..insert(5000, 'new');

      final rows = diffLines(a, b);

      expect(rows.where((r) => r.differs), hasLength(3));
      expect(_lefts(rows), a);
      expect(_rights(rows), b);
    });
  });

  group('collapseSame', () {
    List<DiffRow> same(int n) => [
      for (var i = 0; i < n; i++)
        DiffRow(DiffKind.same, left: '$i', right: '$i'),
    ];

    test('keeps the lines around a difference and counts the rest', () {
      final rows = [
        ...same(5),
        const DiffRow(DiffKind.changed, left: 'a', right: 'b'),
        ...same(5),
      ];

      final out = collapseSame(rows, context: 1);

      expect(_kinds(out), [
        DiffKind.skipped,
        DiffKind.same,
        DiffKind.changed,
        DiffKind.same,
        DiffKind.skipped,
      ]);
      expect(out.first.count, 4);
      expect(out.last.count, 4);
    });

    test('leaves out a run that has no neighbour to show', () {
      final out = collapseSame(same(3), context: 2);

      expect(_kinds(out), [DiffKind.skipped]);
      expect(out.single.count, 3);
    });

    test('closes up differences that are near each other', () {
      final rows = [
        const DiffRow(DiffKind.onlyLeft, left: 'x'),
        ...same(2),
        const DiffRow(DiffKind.onlyRight, right: 'y'),
      ];

      expect(collapseSame(rows, context: 1), rows);
    });

    test('has nothing to do for no rows', () {
      expect(collapseSame(const []), isEmpty);
    });
  });

  group('diffFields', () {
    MapEntry<String, String> f(String name, String value) =>
        MapEntry(name, value);

    test('compares by name and ignores the case of it', () {
      final rows = diffFields(
        [f('Content-Type', 'text/plain'), f('X-Id', '1')],
        [f('content-type', 'text/plain'), f('x-id', '2')],
      );

      expect(_kinds(rows), [DiffKind.same, DiffKind.changed]);
      expect(rows[0].name, 'Content-Type');
      expect(rows[1].left, '1');
      expect(rows[1].right, '2');
    });

    test('says which side has a field the other lacks', () {
      final rows = diffFields(
        [f('a', '1'), f('b', '2')],
        [f('b', '2'), f('c', '3')],
      );

      expect(rows.map((r) => r.name), ['a', 'b', 'c']);
      expect(_kinds(rows), [
        DiffKind.onlyLeft,
        DiffKind.same,
        DiffKind.onlyRight,
      ]);
    });

    test(
      'compares the values of a field that comes more than once in order',
      () {
        final rows = diffFields(
          [f('Set-Cookie', 'a=1'), f('Set-Cookie', 'b=2')],
          [f('set-cookie', 'a=1'), f('set-cookie', 'b=3')],
        );

        expect(rows, hasLength(1));
        expect(rows.single.kind, DiffKind.changed);
        expect(rows.single.left, 'a=1\nb=2');
        expect(rows.single.right, 'a=1\nb=3');
      },
    );

    test('keeps the case of a name apart when asked to', () {
      final rows = diffFields(
        [f('Id', '1')],
        [f('id', '1')],
        ignoreCase: false,
      );

      expect(_kinds(rows), [DiffKind.onlyLeft, DiffKind.onlyRight]);
    });

    test('has no rows for two lists with nothing in them', () {
      expect(diffFields(const [], const []), isEmpty);
    });
  });

  group('changedSpan', () {
    test('leaves out the start and the end the lines share', () {
      final span = changedSpan('"id": 17,', '"id": 4021,');

      expect(span.start, 6);
      expect('"id": 17,'.substring(span.start, span.leftEnd), '17');
      expect('"id": 4021,'.substring(span.start, span.rightEnd), '4021');
    });

    test('is empty on both sides for equal lines', () {
      final span = changedSpan('same', 'same');

      expect(span.leftEnd - span.start, 0);
      expect(span.rightEnd - span.start, 0);
    });

    test('marks the added part of a line that only grew', () {
      final span = changedSpan('abc', 'abcde');

      expect(span.start, 3);
      expect(span.leftEnd, 3);
      expect(span.rightEnd, 5);
    });

    test('does not cut a character made of two code units in half', () {
      const a = 'x😀y';
      const b = 'x😁y';

      final span = changedSpan(a, b);

      expect(a.substring(span.start, span.leftEnd), '😀');
      expect(b.substring(span.start, span.rightEnd), '😁');
    });
  });
}
