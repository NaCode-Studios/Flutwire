import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/src/ui/widgets/pulse.dart';

// A pulse that never stops keeps the app drawing a frame on every refresh for
// nothing, and the inspector stays open for a long time. These check that it
// beats for a while and then holds still, so that a screen at rest costs
// nothing.
const _longerThanTheBeats = Duration(seconds: 12);

Widget _app(Widget child, {bool reducedMotion = false}) => MaterialApp(
  builder: (context, home) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: reducedMotion),
    child: home!,
  ),
  home: Scaffold(body: Center(child: child)),
);

const _dot = SizedBox.square(dimension: 8);

// The page transitions of the app have fades of their own.
Finder _fade() => find.descendant(
  of: find.byType(Pulse),
  matching: find.byType(FadeTransition),
);

double _opacity(WidgetTester tester) =>
    tester.widget<FadeTransition>(_fade()).opacity.value;

void main() {
  testWidgets('beats when it appears and then holds still', (tester) async {
    await tester.pumpWidget(_app(const Pulse(child: _dot)));
    expect(tester.hasRunningAnimations, isTrue);

    await tester.pump(const Duration(milliseconds: 1100));
    expect(_opacity(tester), lessThan(1));

    await tester.pump(_longerThanTheBeats);
    expect(tester.hasRunningAnimations, isFalse);
    expect(_opacity(tester), 1);
  });

  testWidgets('beats again when what it listens to notifies', (tester) async {
    final activity = ValueNotifier(0);
    addTearDown(activity.dispose);
    await tester.pumpWidget(_app(Pulse(restartOn: activity, child: _dot)));
    await tester.pump(_longerThanTheBeats);
    expect(tester.hasRunningAnimations, isFalse);

    activity.value++;
    await tester.pump();
    expect(tester.hasRunningAnimations, isTrue);

    await tester.pump(_longerThanTheBeats);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('notifications during the beats do not stretch them', (
    tester,
  ) async {
    final activity = ValueNotifier(0);
    addTearDown(activity.dispose);
    await tester.pumpWidget(_app(Pulse(restartOn: activity, child: _dot)));

    // A call tells of itself several times as it goes.
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 300));
      activity.value++;
    }
    await tester.pump(const Duration(seconds: 7));

    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('does not beat while it is not active', (tester) async {
    await tester.pumpWidget(_app(const Pulse(active: false, child: _dot)));
    expect(tester.hasRunningAnimations, isFalse);
    expect(_fade(), findsNothing);

    await tester.pumpWidget(_app(const Pulse(child: _dot)));
    expect(tester.hasRunningAnimations, isTrue);

    await tester.pumpWidget(_app(const Pulse(active: false, child: _dot)));
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('stays still when the system asks for reduced motion', (
    tester,
  ) async {
    final activity = ValueNotifier(0);
    addTearDown(activity.dispose);
    await tester.pumpWidget(
      _app(Pulse(restartOn: activity, child: _dot), reducedMotion: true),
    );
    expect(tester.hasRunningAnimations, isFalse);

    activity.value++;
    await tester.pump();
    expect(tester.hasRunningAnimations, isFalse);
  });
}
