import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/flutwire.dart';
import 'package:flutwire/src/l10n/strings_it.dart';
import 'package:flutwire/src/ui/scope.dart';
import 'package:flutwire/src/ui/settings/settings_sheet.dart';
import 'package:flutwire/src/ui/shell.dart';
import 'package:flutwire/src/ui/theme/tokens.dart';

const _channel = MethodChannel('it.nacodestudios.flutwire/native');

const _config = FlutwireConfig(
  enabled: true,
  captureDartIo: false,
  persist: false,
  shortcut: false,
  notification: FlutwireNotificationConfig(enabled: false),
);

Future<void> _openSettings(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: FlutwireShell(
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
  // Without a handler the platform call of `Flutwire.init` never answers.
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (_) async => null);
  });

  tearDown(() async {
    await Flutwire.reset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  group('the appearance setting', () {
    testWidgets('offers the three looks', (tester) async {
      await tester.runAsync(() => Flutwire.init(config: _config));
      await _openSettings(tester);

      expect(find.text('Appearance'.toUpperCase()), findsOneWidget);
      expect(find.text('System'), findsOneWidget);
      expect(find.text('Light'), findsOneWidget);
      expect(find.text('Dark'), findsOneWidget);
    });

    testWidgets('repaints the sheet at once when a look is picked', (
      tester,
    ) async {
      await tester.runAsync(() => Flutwire.init(config: _config));
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await _openSettings(tester);
      expect(_tokensOfSheet(tester).isDark, isTrue);

      await tester.tap(find.text('Light'));
      await tester.pumpAndSettle();

      expect(Flutwire.themeMode, ThemeMode.light);
      expect(_tokensOfSheet(tester).isDark, isFalse);

      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();

      expect(Flutwire.themeMode, ThemeMode.dark);
      expect(_tokensOfSheet(tester).isDark, isTrue);
    });

    testWidgets('follows the device again when System is picked', (
      tester,
    ) async {
      await tester.runAsync(() => Flutwire.init(config: _config));
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await _openSettings(tester);

      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();
      expect(_tokensOfSheet(tester).isDark, isTrue);

      await tester.tap(find.text('System'));
      await tester.pumpAndSettle();
      expect(Flutwire.themeMode, ThemeMode.system);
      expect(_tokensOfSheet(tester).isDark, isFalse);
    });

    testWidgets('marks the look in force as selected', (tester) async {
      await tester.runAsync(() => Flutwire.init(config: _config));
      await _openSettings(tester);

      bool selected(String label) => tester
          .widget<Semantics>(
            find
                .ancestor(
                  of: find.text(label),
                  matching: find.byWidgetPredicate(
                    (widget) =>
                        widget is Semantics && widget.properties.button == true,
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
      await tester.runAsync(
        () => Flutwire.init(
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
      await _openSettings(tester);

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

  group('the saved look', () {
    late Directory root;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('flutwire_theme_');
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    FlutwireConfig onDisk([ThemeMode mode = ThemeMode.system]) =>
        FlutwireConfig(
          enabled: true,
          captureDartIo: false,
          shortcut: false,
          notification: const FlutwireNotificationConfig(enabled: false),
          storagePath: root.path,
          themeMode: mode,
        );

    testWidgets('starts as the app configured it', (tester) async {
      await tester.runAsync(
        () => Flutwire.init(config: onDisk(ThemeMode.dark)),
      );
      expect(Flutwire.themeMode, ThemeMode.dark);
    });

    testWidgets('is remembered across a restart and wins over the config', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await Flutwire.init(config: onDisk(ThemeMode.dark));
        Flutwire.themeMode = ThemeMode.light;
        await Flutwire.reset();
        await Flutwire.init(config: onDisk(ThemeMode.dark));
      });
      expect(Flutwire.themeMode, ThemeMode.light);
    });

    testWidgets('survives clearing the history', (tester) async {
      await tester.runAsync(() async {
        await Flutwire.init(config: onDisk());
        Flutwire.themeMode = ThemeMode.dark;
        await Flutwire.clear(keepPinned: false);
        await Flutwire.reset();
        await Flutwire.init(config: onDisk());
      });
      expect(Flutwire.themeMode, ThemeMode.dark);
    });

    testWidgets('ignores a stored value it does not know', (tester) async {
      await tester.runAsync(() async {
        await File(
          '${root.path}/preferences.json',
        ).writeAsString('{"themeMode":"sepia"}');
        await Flutwire.init(config: onDisk(ThemeMode.light));
      });
      expect(Flutwire.themeMode, ThemeMode.light);
    });
  });
}
