import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/src/version.dart';

String _firstMatch(String path, RegExp pattern) =>
    pattern.firstMatch(File(path).readAsStringSync())!.group(1)!;

void main() {
  test('the version constant matches the pubspec', () {
    final declared = _firstMatch(
      'pubspec.yaml',
      RegExp(r'^version:\s*(\S+)', multiLine: true),
    );

    expect(flutwireVersion, declared);
  });

  test('the Apple pod carries the same version', () {
    final pod = _firstMatch(
      'darwin/flutwire.podspec',
      RegExp(r"s\.version\s*=\s*'([^']+)'"),
    );

    expect(pod, flutwireVersion);
  });
}
