import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/src/coverage.dart';

void main() {
  final start = DateTime.utc(2026, 10, 24, 12);

  test('a note counts each time the same thing is seen again', () {
    final coverage = FlutwireCoverage();
    coverage.report(FlutwireGap.clientBypassesDartIo, 'Dio · api.test', start);
    coverage.report(
      FlutwireGap.clientBypassesDartIo,
      'Dio · api.test',
      start.add(const Duration(seconds: 5)),
    );

    final note = coverage.notes.value.single;
    expect(note.count, 2);
    expect(note.lastSeen, start.add(const Duration(seconds: 5)));
  });

  test('another subject, or another gap, is another note', () {
    final coverage = FlutwireCoverage();
    coverage.report(FlutwireGap.clientBypassesDartIo, 'Dio · api.test', start);
    coverage.report(
      FlutwireGap.clientBypassesDartIo,
      'Dio · other.test',
      start,
    );
    coverage.report(FlutwireGap.otherIsolate, 'Dio in compute', start);

    expect(coverage.notes.value.map((n) => n.subject), [
      'Dio · api.test',
      'Dio · other.test',
      'Dio in compute',
    ]);
  });

  test('resolving a gap forgets its notes and keeps the others', () {
    final coverage = FlutwireCoverage();
    coverage.report(FlutwireGap.captureReplaced, 'HttpOverrides', start);
    coverage.report(FlutwireGap.otherIsolate, 'Dio in compute', start);

    coverage.resolve(FlutwireGap.captureReplaced);

    expect(coverage.notes.value.single.gap, FlutwireGap.otherIsolate);
  });

  test('resolving a gap nobody reported does not tell the listeners', () {
    final coverage = FlutwireCoverage();
    var heard = 0;
    coverage.notes.addListener(() => heard++);

    coverage.resolve(FlutwireGap.captureReplaced);

    expect(heard, 0);
  });

  test('keeps at most the limit, and still counts the notes it has', () {
    final coverage = FlutwireCoverage(limit: 2);
    coverage.report(FlutwireGap.clientBypassesDartIo, 'a', start);
    coverage.report(FlutwireGap.clientBypassesDartIo, 'b', start);
    coverage.report(FlutwireGap.clientBypassesDartIo, 'c', start);
    coverage.report(FlutwireGap.clientBypassesDartIo, 'a', start);

    expect(coverage.notes.value.map((n) => n.subject), ['a', 'b']);
    expect(coverage.notes.value.first.count, 2);
  });
}
