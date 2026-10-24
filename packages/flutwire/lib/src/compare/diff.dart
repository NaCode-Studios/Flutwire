import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show immutable;

/// How one row of a comparison reads.
enum DiffKind {
  /// Both sides have it, and it is the same.
  same,

  /// Both sides have it, and it differs.
  changed,

  /// Only the left side has it.
  onlyLeft,

  /// Only the right side has it.
  onlyRight,

  /// A run of rows that are the same, left out of view. [DiffRow.count] says
  /// how many.
  skipped,
}

/// One row of a comparison: what the left side has, and what the right side
/// has.
@immutable
final class DiffRow {
  /// Creates a row.
  const DiffRow(this.kind, {this.name, this.left, this.right, this.count = 0});

  /// How the row reads.
  final DiffKind kind;

  /// The name of the field the row is about, for a comparison of fields.
  final String? name;

  /// What the left side has, or null when it has nothing here.
  final String? left;

  /// What the right side has, or null when it has nothing here.
  final String? right;

  /// For a [DiffKind.skipped] row, how many rows it stands for.
  final int count;

  /// Whether the two sides disagree on this row.
  bool get differs =>
      kind == DiffKind.changed ||
      kind == DiffKind.onlyLeft ||
      kind == DiffKind.onlyRight;
}

/// Compares two texts line by line and lines the sides up.
///
/// Lines that were replaced pair up as [DiffKind.changed] rows, one against the
/// other, and what is left over is [DiffKind.onlyLeft] or
/// [DiffKind.onlyRight]. The comparison finds the fewest lines to change, up to
/// [maxEdits] of them. Past that the texts have little in common, and the lines
/// are set against each other in the order they come in, which keeps the work
/// bounded.
List<DiffRow> diffLines(
  List<String> left,
  List<String> right, {
  int maxEdits = 1500,
}) {
  var start = 0;
  final shortest = math.min(left.length, right.length);
  while (start < shortest && left[start] == right[start]) {
    start++;
  }
  var leftEnd = left.length;
  var rightEnd = right.length;
  while (leftEnd > start &&
      rightEnd > start &&
      left[leftEnd - 1] == right[rightEnd - 1]) {
    leftEnd--;
    rightEnd--;
  }
  return [
    for (var i = 0; i < start; i++)
      DiffRow(DiffKind.same, left: left[i], right: left[i]),
    ..._between(
      left.sublist(start, leftEnd),
      right.sublist(start, rightEnd),
      maxEdits,
    ),
    for (var i = leftEnd; i < left.length; i++)
      DiffRow(DiffKind.same, left: left[i], right: left[i]),
  ];
}

List<DiffRow> _between(List<String> a, List<String> b, int maxEdits) {
  if (a.isEmpty || b.isEmpty) {
    return [
      for (final line in a) DiffRow(DiffKind.onlyLeft, left: line),
      for (final line in b) DiffRow(DiffKind.onlyRight, right: line),
    ];
  }
  final script = _shortestScript(a, b, maxEdits);
  if (script == null) return _inOrder(a, b);
  final rows = <DiffRow>[];
  final removed = <String>[];
  final added = <String>[];
  void settle() {
    rows.addAll(_pair(removed, added));
    removed.clear();
    added.clear();
  }

  var i = 0;
  var j = 0;
  for (final step in script) {
    if (step == 0) {
      settle();
      rows.add(DiffRow(DiffKind.same, left: a[i], right: b[j]));
      i++;
      j++;
    } else if (step < 0) {
      removed.add(a[i++]);
    } else {
      added.add(b[j++]);
    }
  }
  settle();
  return rows;
}

/// Sets what was removed against what was added, line against line.
List<DiffRow> _pair(List<String> removed, List<String> added) {
  final both = math.min(removed.length, added.length);
  return [
    for (var i = 0; i < both; i++)
      DiffRow(DiffKind.changed, left: removed[i], right: added[i]),
    for (var i = both; i < removed.length; i++)
      DiffRow(DiffKind.onlyLeft, left: removed[i]),
    for (var i = both; i < added.length; i++)
      DiffRow(DiffKind.onlyRight, right: added[i]),
  ];
}

List<DiffRow> _inOrder(List<String> a, List<String> b) =>
    _pair(List.of(a), List.of(b));

/// The steps that turn [a] into [b], found with Myers' algorithm: 0 keeps a
/// line, -1 removes a line of [a] and 1 adds a line of [b]. Returns null when
/// it takes more than [maxEdits] of them.
List<int>? _shortestScript(List<String> a, List<String> b, int maxEdits) {
  final n = a.length;
  final m = b.length;
  final limit = math.min(n + m, maxEdits);
  final offset = limit + 1;
  // The furthest line of [a] reached on each diagonal, by the number of edits.
  final reach = Int32List(2 * limit + 3);
  // What `reach` held when each round began, trimmed to the diagonals the
  // round can read, so that the script can be walked back.
  final trace = <Int32List>[];
  for (var d = 0; d <= limit; d++) {
    trace.add(reach.sublist(offset - d - 1, offset + d + 2));
    for (var k = -d; k <= d; k += 2) {
      var x =
          k == -d || (k != d && reach[offset + k - 1] < reach[offset + k + 1])
          ? reach[offset + k + 1]
          : reach[offset + k - 1] + 1;
      var y = x - k;
      while (x < n && y < m && a[x] == b[y]) {
        x++;
        y++;
      }
      reach[offset + k] = x;
      if (x >= n && y >= m) return _walkBack(trace, n, m, d);
    }
  }
  return null;
}

List<int> _walkBack(List<Int32List> trace, int n, int m, int edits) {
  final steps = <int>[];
  var x = n;
  var y = m;
  for (var d = edits; d >= 0; d--) {
    final before = trace[d];
    int reached(int k) => before[k + d + 1];
    final k = x - y;
    final from = k == -d || (k != d && reached(k - 1) < reached(k + 1))
        ? k + 1
        : k - 1;
    final fromX = reached(from);
    final fromY = fromX - from;
    while (x > fromX && y > fromY) {
      steps.add(0);
      x--;
      y--;
    }
    if (d > 0) steps.add(x == fromX ? 1 : -1);
    x = fromX;
    y = fromY;
  }
  return steps.reversed.toList();
}

/// Leaves out the rows that are the same, except for [context] of them on each
/// side of a row that is not. A run that is left out becomes one
/// [DiffKind.skipped] row.
List<DiffRow> collapseSame(List<DiffRow> rows, {int context = 2}) {
  final shown = List<bool>.filled(rows.length, false);
  for (var i = 0; i < rows.length; i++) {
    if (rows[i].kind == DiffKind.same) continue;
    final from = math.max(0, i - context);
    final to = math.min(rows.length - 1, i + context);
    for (var j = from; j <= to; j++) {
      shown[j] = true;
    }
  }
  final out = <DiffRow>[];
  var skipped = 0;
  void closeRun() {
    if (skipped > 0) out.add(DiffRow(DiffKind.skipped, count: skipped));
    skipped = 0;
  }

  for (var i = 0; i < rows.length; i++) {
    if (shown[i]) {
      closeRun();
      out.add(rows[i]);
    } else {
      skipped++;
    }
  }
  closeRun();
  return out;
}

/// Compares two lists of fields by name: header fields, query parameters.
///
/// A name that comes more than once, as `Set-Cookie` does, has its values
/// compared in order, and a row holds them one to a line. Names are matched
/// without regard to case unless [ignoreCase] is false. The rows follow the
/// order of the left side, then the fields only the right side has.
List<DiffRow> diffFields(
  Iterable<MapEntry<String, String>> left,
  Iterable<MapEntry<String, String>> right, {
  bool ignoreCase = true,
}) {
  final a = _group(left, ignoreCase);
  final b = _group(right, ignoreCase);
  return [
    for (final entry in a.entries)
      if (b[entry.key] case final other?)
        DiffRow(
          _sameValues(entry.value.values, other.values)
              ? DiffKind.same
              : DiffKind.changed,
          name: entry.value.name,
          left: entry.value.values.join('\n'),
          right: other.values.join('\n'),
        )
      else
        DiffRow(
          DiffKind.onlyLeft,
          name: entry.value.name,
          left: entry.value.values.join('\n'),
        ),
    for (final entry in b.entries)
      if (!a.containsKey(entry.key))
        DiffRow(
          DiffKind.onlyRight,
          name: entry.value.name,
          right: entry.value.values.join('\n'),
        ),
  ];
}

typedef _Field = ({String name, List<String> values});

Map<String, _Field> _group(
  Iterable<MapEntry<String, String>> fields,
  bool ignoreCase,
) {
  final grouped = <String, _Field>{};
  for (final field in fields) {
    final key = ignoreCase ? field.key.toLowerCase() : field.key;
    (grouped[key] ??= (
      name: field.key,
      values: <String>[],
    )).values.add(field.value);
  }
  return grouped;
}

bool _sameValues(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// What differs inside two lines: what is left of each once the start and the
/// end they share are taken off. [start] is where the difference begins in
/// both, and [leftEnd] and [rightEnd] are where it ends.
({int start, int leftEnd, int rightEnd}) changedSpan(String a, String b) {
  final shortest = math.min(a.length, b.length);
  var start = 0;
  while (start < shortest && a.codeUnitAt(start) == b.codeUnitAt(start)) {
    start++;
  }
  // Half of a surrogate pair is not a character to highlight.
  if (start > 0 && _isHighSurrogate(a.codeUnitAt(start - 1))) start--;
  var tail = 0;
  while (tail < shortest - start &&
      a.codeUnitAt(a.length - 1 - tail) == b.codeUnitAt(b.length - 1 - tail)) {
    tail++;
  }
  if (tail > 0 && _isLowSurrogate(a.codeUnitAt(a.length - tail))) tail--;
  return (start: start, leftEnd: a.length - tail, rightEnd: b.length - tail);
}

bool _isHighSurrogate(int unit) => unit >= 0xD800 && unit <= 0xDBFF;

bool _isLowSurrogate(int unit) => unit >= 0xDC00 && unit <= 0xDFFF;
