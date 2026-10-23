import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'capture/recorder.dart';
import 'config.dart';
import 'diagnostics.dart';
import 'model/call.dart';
import 'model/headers.dart';
import 'runtime.dart';
import 'store/store.dart';
import 'ui/overlay/floating_button.dart';

/// The entry point of Flutwire.
///
/// ```dart
/// Future<void> main() async {
///   await Flutwire.init();
///   runApp(const MyApp());
/// }
/// ```
///
/// From then on every call made through `dart:io` is recorded, a notification
/// lists the latest ones, and tapping it opens the inspector. In a release
/// build `init` does nothing, and every other member is a harmless no-op.
abstract final class Flutwire {
  static final ValueNotifier<FlutwireRuntime?> _runtime = ValueNotifier(null);
  static final ValueNotifier<List<FlutwireCall>> _none = ValueNotifier(
    const [],
  );
  static Future<void>? _starting;

  /// Give this to the app's navigator so the inspector opens above the app's
  /// own routes. It is optional: without it Flutwire finds the root navigator
  /// itself.
  ///
  /// ```dart
  /// MaterialApp(navigatorKey: Flutwire.navigatorKey, ...)
  /// ```
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>(debugLabel: 'Flutwire');

  /// Starts recording. Call it once, as early as possible in `main`: only the
  /// clients created after it are seen. Calling it again does nothing.
  ///
  /// It never throws. If Flutwire cannot start, the app carries on without it.
  static Future<void> init({FlutwireConfig config = const FlutwireConfig()}) =>
      _starting ??= _start(config);

  static Future<void> _start(FlutwireConfig config) async {
    try {
      _runtime.value = await FlutwireRuntime.start(
        config,
        navigatorKey: navigatorKey,
      );
    } on Object catch (error, stack) {
      reportProblem(
        'Could not start, so Flutwire stays off.',
        error: error,
        stack: stack,
      );
    }
  }

  /// Whether Flutwire is recording in this build.
  static bool get isActive => _runtime.value != null;

  /// The configuration in force, or the defaults before [init] has run.
  static FlutwireConfig get config =>
      _runtime.value?.config ?? const FlutwireConfig();

  /// The recorded calls, newest first. Empty while Flutwire is not recording.
  static ValueListenable<List<FlutwireCall>> get calls =>
      _runtime.value?.store.calls ?? _none;

  /// The store behind [calls], for reading the full call with its bodies.
  static FlutwireStore? get store => _runtime.value?.store;

  /// Whether recording is paused. Calls made while paused are not recorded.
  static bool get isPaused => _runtime.value?.paused.value ?? false;

  static set isPaused(bool value) => _runtime.value?.paused.value = value;

  /// Whether the `dart:io` capture is installed. Client adapters check it to
  /// avoid recording a call twice.
  static bool get wireCaptureActive =>
      _runtime.value?.engine.wireCaptureActive ?? false;

  /// For `MaterialApp.builder` and `WidgetsApp.builder`: floats a small button
  /// above the app that opens the inspector, and listens for Ctrl or Cmd with
  /// Shift and L. It is meant for the web, Windows and Linux, where there is no
  /// notification to open the inspector from, and it shows only there unless
  /// [FlutwireConfig.floatingButton] says otherwise.
  ///
  /// ```dart
  /// MaterialApp(builder: Flutwire.builder, ...)
  /// ```
  static Widget builder(BuildContext context, Widget? child) => FlutwireOverlay(
    session: _runtime,
    child: child ?? const SizedBox.shrink(),
  );

  /// Starts recording one call. This is what a capture adapter calls; an app
  /// that only uses `dart:io` never needs it. Returns null when the call
  /// should not be recorded.
  static FlutwireCallRecorder? begin({
    required String method,
    required Uri uri,
    required FlutwireSource source,
    FlutwireHeaders requestHeaders = FlutwireHeaders.empty,
  }) => _runtime.value?.engine.begin(
    method: method,
    uri: uri,
    source: source,
    requestHeaders: requestHeaders,
  );

  /// Removes every recorded call, except the pinned ones when [keepPinned] is
  /// true.
  static Future<void> clear({bool keepPinned = true}) async {
    await _runtime.value?.clear(keepPinned: keepPinned);
  }

  /// Opens the inspector above the app. [context] is optional: without one
  /// the navigator from [navigatorKey], or else the root navigator, is used.
  ///
  /// Does nothing if the inspector is already open or Flutwire is not
  /// recording.
  static Future<void> open([BuildContext? context]) async {
    await _runtime.value?.openInspector(context);
  }

  /// Stops recording and releases everything. Meant for tests.
  @visibleForTesting
  static Future<void> reset() async {
    final runtime = _runtime.value;
    _runtime.value = null;
    _starting = null;
    await runtime?.dispose();
  }
}
