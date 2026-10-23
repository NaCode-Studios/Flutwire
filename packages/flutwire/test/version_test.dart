import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/src/version.dart';

void main() {
  test('the version constant matches the pubspec', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final declared = RegExp(
      r'^version:\s*(\S+)',
      multiLine: true,
    ).firstMatch(pubspec)!.group(1);
    expect(flutwireVersion, declared);
  });
}
