// The probe that tells whether the dart:io capture would still see a call. It
// looks at what `HttpClient()` hands out, so these tests avoid the widget test
// binding, which replaces every HttpClient.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/src/capture/wire/wire_io.dart';
import 'package:flutwire/src/config.dart';
import 'package:flutwire/src/coverage.dart';
import 'package:flutwire/src/engine.dart';

/// Overrides that know nothing of Flutwire's, as an app's own would be if it
/// set `HttpOverrides.global` after `Flutwire.init`.
class _Replacing extends HttpOverrides {}

/// Overrides that sit on top of the ones before them and hand every client on.
class _Chaining extends HttpOverrides {
  _Chaining(this.previous);

  final HttpOverrides? previous;

  @override
  HttpClient createHttpClient(SecurityContext? context) => previous != null
      ? previous!.createHttpClient(context)
      : super.createHttpClient(context);
}

void main() {
  late FlutwireEngine engine;
  late void Function() uninstall;

  setUp(() {
    engine = FlutwireEngine(config: const FlutwireConfig(enabled: true));
    uninstall = installWireCapture(engine);
  });

  tearDown(() async {
    uninstall();
    HttpOverrides.global = null;
    await engine.dispose();
  });

  test('sees calls right after it is installed', () {
    expect(engine.wireCaptureProbe, isNotNull);
    expect(engine.verifyCapture(), isTrue);
    expect(engine.coverage.notes.value, isEmpty);
  });

  test('says so when other overrides replaced it', () {
    HttpOverrides.global = _Replacing();

    expect(engine.verifyCapture(), isFalse);
    expect(engine.coverage.notes.value.single.gap, FlutwireGap.captureReplaced);
  });

  test('overrides that chain to it are not a replacement', () {
    HttpOverrides.global = _Chaining(HttpOverrides.current);

    expect(engine.verifyCapture(), isTrue);
    expect(engine.coverage.notes.value, isEmpty);
  });

  test('forgets the note once the capture is back', () {
    final ours = HttpOverrides.current;
    HttpOverrides.global = _Replacing();
    engine.verifyCapture();
    expect(engine.coverage.notes.value, hasLength(1));

    HttpOverrides.global = ours;

    expect(engine.verifyCapture(), isTrue);
    expect(engine.coverage.notes.value, isEmpty);
  });

  test('takes the probe away with the capture', () {
    uninstall();

    expect(engine.wireCaptureActive, isFalse);
    expect(engine.wireCaptureProbe, isNull);
  });
}
