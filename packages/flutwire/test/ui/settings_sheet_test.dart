import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/flutwire.dart';
import 'package:flutwire/src/l10n/strings_it.dart';
import 'package:flutwire/src/platform/native.dart';
import 'package:flutwire/src/ui/scope.dart';
import 'package:flutwire/src/ui/settings/settings_sheet.dart';
import 'package:flutwire/src/ui/shell.dart';
import 'package:flutwire/src/ui/theme/tokens.dart';

import 'calls.dart';
import 'fake_session.dart';

Future<void> _openSettings(WidgetTester tester, FakeSession session) async {
  await tester.pumpWidget(
    MaterialApp(
      home: FlutwireShell(
        session: session,
        child: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showSettingsSheet(context),
                child: const Text('open settings'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open settings'));
  await tester.pumpAndSettle();
}

FlutwireTokens _tokensOfSheet(WidgetTester tester) =>
    FlutwireTokens.of(tester.element(find.text('APPEARANCE')));

void main() {
  group('the recording switch', () {
    testWidgets('shows whether Flutwire is recording', (tester) async {
      final session = FakeSession();
      await _openSettings(tester, session);

      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
      expect(find.text('Paused'), findsNothing);
    });

    testWidgets('pauses and resumes the recording', (tester) async {
      final session = FakeSession();
      await _openSettings(tester, session);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(session.paused.value, isTrue);
      expect(find.text('Paused'), findsOneWidget);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(session.paused.value, isFalse);
    });
  });

  group('the appearance setting', () {
    testWidgets('offers the three looks', (tester) async {
      await _openSettings(tester, FakeSession());

      expect(find.text('Appearance'.toUpperCase()), findsOneWidget);
      expect(find.text('System'), findsOneWidget);
      expect(find.text('Light'), findsOneWidget);
      expect(find.text('Dark'), findsOneWidget);
    });

    testWidgets('repaints the sheet at once when a look is picked', (
      tester,
    ) async {
      final session = FakeSession(themeMode: ThemeMode.system);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await _openSettings(tester, session);
      expect(_tokensOfSheet(tester).isDark, isTrue);

      await tester.tap(find.text('Light'));
      await tester.pumpAndSettle();

      expect(session.themeMode.value, ThemeMode.light);
      expect(_tokensOfSheet(tester).isDark, isFalse);

      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();

      expect(session.themeMode.value, ThemeMode.dark);
      expect(_tokensOfSheet(tester).isDark, isTrue);
    });

    testWidgets('follows the device again when System is picked', (
      tester,
    ) async {
      final session = FakeSession(themeMode: ThemeMode.system);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await _openSettings(tester, session);

      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();
      expect(_tokensOfSheet(tester).isDark, isTrue);

      await tester.tap(find.text('System'));
      await tester.pumpAndSettle();
      expect(session.themeMode.value, ThemeMode.system);
      expect(_tokensOfSheet(tester).isDark, isFalse);
    });

    testWidgets('marks the look in force as selected', (tester) async {
      await _openSettings(tester, FakeSession());

      bool selected(String label) => tester
          .widget<Semantics>(
            find
                .ancestor(
                  of: find.text(label),
                  matching: find.byWidgetPredicate(
                    (widget) =>
                        widget is Semantics &&
                        (widget.properties.button ?? false),
                  ),
                )
                .first,
          )
          .properties
          .selected!;

      await tester.tap(find.text('Light'));
      await tester.pumpAndSettle();
      expect(selected('Light'), isTrue);
      expect(selected('Dark'), isFalse);
    });

    testWidgets('speaks the language of the inspector', (tester) async {
      await _openSettings(
        tester,
        FakeSession(
          config: const FlutwireConfig(
            enabled: true,
            captureDartIo: false,
            persist: false,
            shortcut: false,
            notification: FlutwireNotificationConfig(enabled: false),
            locale: Locale('it'),
          ),
        ),
      );

      expect(
        find.text(const FlutwireStringsIt().appearanceSetting.toUpperCase()),
        findsOneWidget,
      );
      expect(find.text('Chiaro'), findsOneWidget);
      expect(find.text('Scuro'), findsOneWidget);
      expect(
        FlutwireScope.stringsOf(tester.element(find.text('Chiaro'))),
        isA<FlutwireStringsIt>(),
      );
    });
  });

  group('the notification card', () {
    FakeSession withNotifications(FlutwireNotificationPermission permission) =>
        FakeSession(
          permission: permission,
          config: const FlutwireConfig(
            enabled: true,
            captureDartIo: false,
            persist: false,
            shortcut: false,
            locale: Locale('en'),
          ),
        );

    testWidgets('says so when the notification is turned off in the config', (
      tester,
    ) async {
      await _openSettings(tester, FakeSession());

      expect(find.text('This platform has no notification'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('says so when the platform has none', (tester) async {
      await _openSettings(
        tester,
        withNotifications(FlutwireNotificationPermission.unsupported),
      );

      expect(find.text('This platform has no notification'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('confirms that the notification is on', (tester) async {
      await _openSettings(
        tester,
        withNotifications(FlutwireNotificationPermission.granted),
      );

      expect(
        find.text('Showing the latest calls in the shade'),
        findsOneWidget,
      );
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('sends the user to the system settings when refused', (
      tester,
    ) async {
      final session = withNotifications(FlutwireNotificationPermission.denied);
      await _openSettings(tester, session);

      expect(
        find.text('Notifications are turned off for this app'),
        findsOneWidget,
      );
      await tester.tap(find.text('Open system settings'));
      await tester.pumpAndSettle();

      expect(session.settingsOpened, 1);
    });

    testWidgets('asks for the permission when it was never asked', (
      tester,
    ) async {
      final session = withNotifications(
        FlutwireNotificationPermission.notDetermined,
      );
      await _openSettings(tester, session);

      await tester.tap(find.text('Allow notifications'));
      await tester.pumpAndSettle();

      expect(session.permissionRequests, 1);
      expect(
        find.text('Showing the latest calls in the shade'),
        findsOneWidget,
      );
    });
  });

  testWidgets('says how long the history is kept and how big it is', (
    tester,
  ) async {
    final session = FakeSession(
      calls: [
        makeCall(1),
        makeCall(
          2,
          status: null,
          state: FlutwireCallState.failed,
          error: const FlutwireError(type: 'SocketException', message: 'down'),
        ),
      ],
    );
    await _openSettings(tester, session);

    expect(find.text('1 week'), findsOneWidget);
    expect(find.text('2 calls · 1 failed'), findsOneWidget);
  });
}
