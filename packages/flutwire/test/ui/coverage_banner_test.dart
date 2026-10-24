import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/flutwire.dart';
import 'package:flutwire/src/l10n/strings_en.dart';
import 'package:flutwire/src/l10n/strings_it.dart';
import 'package:flutwire/src/ui/inspector/coverage_banner.dart';

import 'fake_session.dart';
import 'harness.dart';

FlutwireCoverageNote note(FlutwireGap gap, String subject, {int count = 1}) =>
    FlutwireCoverageNote(
      gap: gap,
      subject: subject,
      lastSeen: DateTime.utc(2026, 10, 24, 12),
      count: count,
    );

void main() {
  testWidgets('says nothing while nothing is wrong', (tester) async {
    await pumpFlutwire(tester, const CoverageBanner());

    expect(find.text('Flutwire may be missing calls'), findsNothing);
  });

  testWidgets('appears when a note arrives and goes when it is resolved', (
    tester,
  ) async {
    final session = FakeSession();
    await pumpFlutwire(tester, const CoverageBanner(), session: session);

    session.coverage.value = [note(FlutwireGap.otherIsolate, 'Dio in compute')];
    await tester.pump();
    expect(find.text('Flutwire may be missing calls'), findsOneWidget);
    expect(find.text('Details'), findsOneWidget);

    session.coverage.value = const [];
    await tester.pump();
    expect(find.text('Flutwire may be missing calls'), findsNothing);
  });

  testWidgets('opens each reason with what happened and what to do', (
    tester,
  ) async {
    final session = FakeSession();
    session.coverage.value = [
      note(FlutwireGap.clientBypassesDartIo, 'Dio · api.test', count: 3),
      note(FlutwireGap.captureReplaced, 'HttpOverrides'),
    ];
    await pumpFlutwire(tester, const CoverageBanner(), session: session);

    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();

    expect(find.text('What Flutwire may not see'), findsOneWidget);
    expect(find.text('A client that does not use dart:io'), findsOneWidget);
    expect(find.textContaining('Dio · api.test made a call'), findsOneWidget);
    expect(find.textContaining('Pass force: true'), findsOneWidget);
    expect(find.text('SEEN 3 TIMES'), findsOneWidget);
    expect(find.text('The dart:io capture was replaced'), findsOneWidget);
    expect(find.textContaining('before Flutwire.init'), findsOneWidget);
  });

  testWidgets('does not count a replaced capture like missed calls', (
    tester,
  ) async {
    final session = FakeSession();
    session.coverage.value = [
      note(FlutwireGap.captureReplaced, 'HttpOverrides', count: 4),
    ];
    await pumpFlutwire(tester, const CoverageBanner(), session: session);

    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();

    expect(find.text('The dart:io capture was replaced'), findsOneWidget);
    expect(find.textContaining('SEEN'), findsNothing);
  });

  testWidgets('says the same in Italian', (tester) async {
    final session = FakeSession(
      config: const FlutwireConfig(
        enabled: true,
        captureDartIo: false,
        persist: false,
        shortcut: false,
        locale: Locale('it'),
        notification: FlutwireNotificationConfig(enabled: false),
      ),
    );
    session.coverage.value = [
      note(FlutwireGap.otherIsolate, 'Dio in compute', count: 2),
    ];
    await pumpFlutwire(
      tester,
      const CoverageBanner(),
      session: session,
      strings: const FlutwireStringsIt(),
    );

    expect(
      find.text('Flutwire potrebbe non vedere alcune chiamate'),
      findsOneWidget,
    );
    await tester.tap(find.text('Dettagli'));
    await tester.pumpAndSettle();

    expect(find.text('Una chiamata da un altro isolate'), findsOneWidget);
    expect(find.textContaining("Fai la chiamata nell'isolate"), findsOneWidget);
    expect(find.text('VISTO 2 VOLTE'), findsOneWidget);
  });

  test(
    'every gap has a title, an explanation and a way out in both languages',
    () {
      for (final strings in const [FlutwireStringsEn(), FlutwireStringsIt()]) {
        for (final gap in FlutwireGap.values) {
          expect(strings.coverageGapTitle(gap), isNotEmpty, reason: '$gap');
          expect(strings.coverageGapWhat(gap, 'x'), isNotEmpty, reason: '$gap');
          expect(strings.coverageGapFix(gap), isNotEmpty, reason: '$gap');
        }
      }
    },
  );
}
