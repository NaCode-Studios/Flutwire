import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/foundation.dart' as foundation show compute;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show RootIsolateToken;

import 'capture/recorder.dart';
import 'config.dart';
import 'coverage.dart';
import 'diagnostics.dart';
import 'engine.dart' show FlutwireEngine, FlutwireStandDown;
import 'isolate_bridge.dart';
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
  static final ValueNotifier<List<FlutwireCoverageNote>> _noNotes =
      ValueNotifier(const []);
  static Future<void>? _starting;

  /// The engine that records in this isolate: the app's, or the one an isolate
  /// other than the main one got by attaching.
  static FlutwireEngine? get _engine =>
      _runtime.value?.engine ?? FlutwireIsolateLink.engine;

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
  static bool get wireCaptureActive => _engine?.wireCaptureActive ?? false;

  /// For `MaterialApp.builder` and `WidgetsApp.builder`: floats a small button
  /// above the app that opens the inspector, and listens for Ctrl or Cmd with
  /// Shift and L. It is meant for the web, Windows and Linux, where there is no
  /// notification to open the inspector from, and it shows only there unless
  /// [FlutwireConfig.floatingButton] says otherwise.
  ///
  /// It is also what lets the inspector be docked: put in a panel beside the
  /// app, under it or to its right, which can be dragged to any size, so that
  /// the app and its traffic are in view together.
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
  }) {
    final engine = _engine;
    if (engine == null) {
      // An adapter running where nothing records: in a release build, or in an
      // isolate other than the one the app runs in that did not attach to
      // Flutwire. Only the second is news.
      if (!isRootIsolate()) FlutwireIsolateBridge.tell(source);
      return null;
    }
    return engine.begin(
      method: method,
      uri: uri,
      source: source,
      requestHeaders: requestHeaders,
    );
  }

  /// Records the calls made in this isolate in the history of the app.
  ///
  /// Overrides belong to one isolate, so a call made with `Isolate.run` or
  /// `compute` is not seen unless that isolate attaches. Call it first thing in
  /// an isolate you spawn yourself, and [detach] when the isolate is done with
  /// the network. For `Isolate.run` and `compute` use [run] and [compute]
  /// instead, which do both.
  ///
  /// Does nothing in the main isolate, and where the app's Flutwire is not
  /// recording. It never throws.
  static Future<void> attach() async {
    if (isRootIsolate()) return;
    await FlutwireIsolateLink.attach();
  }

  /// Stops recording this isolate's calls, which [attach] started. Calls still
  /// in flight keep reporting.
  static Future<void> detach() => FlutwireIsolateLink.detach();

  /// Runs [computation] in a new isolate, as `Isolate.run` does, and records
  /// the calls it makes in the history of the app.
  ///
  /// ```dart
  /// final todos = await Flutwire.run(() => fetchTodos());
  /// ```
  ///
  /// Without Flutwire running it is `Isolate.run`. On the web, where there are
  /// no isolates, it runs [computation] where it is.
  static Future<R> run<R>(
    FutureOr<R> Function() computation, {
    String? debugName,
  }) {
    if (kIsWeb) return Future<R>.sync(computation);
    return Isolate.run<R>(() => _attached(computation), debugName: debugName);
  }

  /// Runs [callback] with [message] in a new isolate, as `compute` does, and
  /// records the calls it makes in the history of the app.
  ///
  /// ```dart
  /// final todos = await Flutwire.compute(fetchTodos, 'https://example.com');
  /// ```
  static Future<R> compute<M, R>(
    FutureOr<R> Function(M message) callback,
    M message, {
    String? debugLabel,
  }) => foundation.compute<M, R>(
    (M m) => _attached(() => callback(m)),
    message,
    debugLabel: debugLabel,
  );

  static Future<R> _attached<R>(FutureOr<R> Function() computation) async {
    await attach();
    try {
      return await computation();
    } finally {
      await detach();
    }
  }

  /// Whether this code runs in the isolate the app runs in. Replaced in tests,
  /// which have no second isolate with Flutter in it.
  @visibleForTesting
  static bool Function() isRootIsolate = () =>
      RootIsolateToken.instance != null;

  /// Starts watching a call that a client adapter stands down for because the
  /// `dart:io` capture records it. This is what an adapter calls; an app never
  /// needs it.
  ///
  /// Call [FlutwireStandDown.finish] on the result when the call is over,
  /// whatever its outcome. If the capture never saw the call, the inspector
  /// says that Flutwire may be missing calls and why. Returns null when there
  /// is nothing to watch.
  static FlutwireStandDown? watchStandDown({
    required String method,
    required Uri uri,
    required String client,
  }) => _engine?.watchStandDown(method: method, uri: uri, client: client);

  /// What Flutwire has noticed about its own blind spots. Empty while nothing
  /// is wrong, which is also what it is while Flutwire is not recording.
  static ValueListenable<List<FlutwireCoverageNote>> get coverage =>
      _runtime.value?.engine.coverage.notes ?? _noNotes;

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
