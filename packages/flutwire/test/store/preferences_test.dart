import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/src/config.dart';
import 'package:flutwire/src/store/disk_store_io.dart';
import 'package:flutwire/src/store/preferences.dart';
import 'package:flutwire/src/store/preferences_io.dart';

void main() {
  group('MemoryFlutwirePreferences', () {
    test('reads back what it was given', () async {
      final preferences = MemoryFlutwirePreferences({'a': '1'});
      expect(preferences.read('a'), '1');
      expect(preferences.read('b'), isNull);
      await preferences.write('b', '2');
      expect(preferences.read('b'), '2');
    });

    test('forgets a key written as null', () async {
      final preferences = MemoryFlutwirePreferences({'a': '1'});
      await preferences.write('a', null);
      expect(preferences.read('a'), isNull);
    });

    test('does not share state with the map it was built from', () async {
      final initial = {'a': '1'};
      final preferences = MemoryFlutwirePreferences(initial);
      await preferences.write('a', '2');
      expect(initial['a'], '1');
    });
  });

  group('FileFlutwirePreferences', () {
    late Directory root;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('flutwire_prefs_');
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    test('starts empty when there is no file', () async {
      final preferences = await FileFlutwirePreferences.open(root);
      expect(preferences.read('themeMode'), isNull);
    });

    test('keeps what was written across a reopen', () async {
      final first = await FileFlutwirePreferences.open(root);
      await first.write('themeMode', 'light');
      await first.write('other', 'x');
      await first.settled;

      final second = await FileFlutwirePreferences.open(root);
      expect(second.read('themeMode'), 'light');
      expect(second.read('other'), 'x');
    });

    test('forgets a key for good', () async {
      final first = await FileFlutwirePreferences.open(root);
      await first.write('themeMode', 'dark');
      await first.write('themeMode', null);
      await first.settled;

      final second = await FileFlutwirePreferences.open(root);
      expect(second.read('themeMode'), isNull);
    });

    test('creates the folder when it does not exist yet', () async {
      final nested = Directory('${root.path}/not/yet');
      final preferences = await FileFlutwirePreferences.open(nested);
      await preferences.write('themeMode', 'dark');
      await preferences.settled;
      expect(File('${nested.path}/preferences.json').existsSync(), isTrue);
    });

    test('treats a damaged file as empty instead of failing', () async {
      await File('${root.path}/preferences.json').writeAsString('{not json');
      final preferences = await FileFlutwirePreferences.open(root);
      expect(preferences.read('themeMode'), isNull);

      await preferences.write('themeMode', 'dark');
      await preferences.settled;
      final reopened = await FileFlutwirePreferences.open(root);
      expect(reopened.read('themeMode'), 'dark');
    });

    test('ignores values that are not text', () async {
      await File(
        '${root.path}/preferences.json',
      ).writeAsString(jsonEncode({'themeMode': 3, 'ok': 'yes'}));
      final preferences = await FileFlutwirePreferences.open(root);
      expect(preferences.read('themeMode'), isNull);
      expect(preferences.read('ok'), 'yes');
    });

    test('leaves no temporary file behind', () async {
      final preferences = await FileFlutwirePreferences.open(root);
      await preferences.write('themeMode', 'light');
      await preferences.settled;
      final names = root.listSync().map((e) => e.uri.pathSegments.last);
      expect(names, ['preferences.json']);
    });
  });

  group('DiskFlutwireStore preferences', () {
    late Directory root;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('flutwire_store_prefs_');
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    test('survive a restart and clearing the history', () async {
      const config = FlutwireConfig(enabled: true);
      final first = await DiskFlutwireStore.open(root, config);
      await first.preferences.write('themeMode', 'light');
      await first.clear(keepPinned: false);
      await first.dispose();

      final second = await DiskFlutwireStore.open(root, config);
      expect(second.preferences.read('themeMode'), 'light');
      await second.dispose();
    });
  });
}
