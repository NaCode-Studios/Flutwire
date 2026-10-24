import 'package:flutter/painting.dart' show Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/src/ui/widgets/metric_strip.dart';

import 'calls.dart';
import 'harness.dart';

const _labels = ['CALLS', 'FAILED', 'AVERAGE', 'TRANSFERRED'];

void main() {
  testWidgets('puts the four numbers in a row when they fit', (tester) async {
    // The test font is wider than the one the inspector ships with.
    await pumpFlutwire(
      tester,
      MetricStrip(calls: [makeCall(1)]),
      size: const Size(700, 600),
    );

    final tops = [for (final l in _labels) tester.getTopLeft(find.text(l)).dy];
    expect(tops.toSet(), hasLength(1));
  });

  testWidgets('puts them in two rows of two when they do not', (tester) async {
    // The width of the inspector in a panel of the least size.
    await pumpFlutwire(
      tester,
      MetricStrip(calls: [makeCall(1)]),
      size: const Size(280, 600),
    );

    final calls = tester.getTopLeft(find.text('CALLS'));
    final failed = tester.getTopLeft(find.text('FAILED'));
    final average = tester.getTopLeft(find.text('AVERAGE'));
    final transferred = tester.getTopLeft(find.text('TRANSFERRED'));
    expect(failed.dy, calls.dy);
    expect(transferred.dy, average.dy);
    expect(average.dy, greaterThan(calls.dy));
    expect(failed.dx, greaterThan(calls.dx));
    expect(transferred.dx, greaterThan(average.dx));
  });

  testWidgets('never breaks a label into lines', (tester) async {
    for (final width in [280.0, 340.0, 420.0, 520.0, 700.0]) {
      await pumpFlutwire(
        tester,
        MetricStrip(calls: [makeCall(1)]),
        size: Size(width, 600),
      );

      for (final label in _labels) {
        expect(
          tester.getSize(find.text(label)).height,
          lessThan(20),
          reason: '$label at $width',
        );
      }
    }
  });
}
