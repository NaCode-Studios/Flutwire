import 'package:flutter/foundation.dart';

import 'capture/recorder.dart';
import 'config.dart';
import 'coverage.dart';
import 'diagnostics.dart';
import 'model/body.dart';
import 'model/call.dart';
import 'model/headers.dart';
import 'store/store.dart';

/// The part of Flutwire that records calls: it decides whether a call is
/// recorded, hands out recorders, and writes what they publish to the store.
///
/// The `Flutwire` class holds one of these for the app. It is a plain object
/// so that tests can build as many as they need.
final class FlutwireEngine implements FlutwireRecorderHost {
  /// Creates an engine that writes to [store], or to a memory store sized by
  /// [config] when none is given.
  FlutwireEngine({
    required this.config,
    FlutwireStore? store,
    DateTime Function()? clock,
  }) : store =
           store ??
           MemoryFlutwireStore(
             maxCalls: config.maxCalls,
             maxBytes: config.maxMemoryBytes,
           ),
       _clock = clock ?? DateTime.now;

  @override
  final FlutwireConfig config;

  /// Where recorded calls go.
  final FlutwireStore store;

  final DateTime Function() _clock;
  int _lastId = 0;
  bool _reportedInternalError = false;

  /// Whether the `dart:io` capture is installed for this engine. Capture
  /// adapters for a single client stand down while it is, because it already
  /// sees their calls.
  bool wireCaptureActive = false;

  /// Set by the `dart:io` capture: whether it would still see a call made now.
  /// Null where there is no capture.
  bool Function()? wireCaptureProbe;

  /// What Flutwire has noticed about its own blind spots.
  final FlutwireCoverage coverage = FlutwireCoverage();

  /// The latest calls the `dart:io` capture began, for telling whether it saw
  /// the call an adapter stood down for. The store cannot answer that: it
  /// tells its listeners about new calls only every so often.
  final List<_Began> _recentIo = [];

  /// How many failures inside Flutwire were swallowed. A test or a bug report
  /// can read it; the app never sees them.
  int internalErrorCount = 0;

  /// Whether recording is paused. Calls made while paused are not recorded.
  final ValueNotifier<bool> paused = ValueNotifier(false);

  @override
  DateTime now() => _clock();

  /// Starts recording a call, or returns null when it should not be recorded:
  /// recording is off or paused, or an ignore rule matches.
  FlutwireCallRecorder? begin({
    required String method,
    required Uri uri,
    required FlutwireSource source,
    FlutwireHeaders requestHeaders = FlutwireHeaders.empty,
  }) {
    try {
      final upper = method.toUpperCase();
      if (!_shouldRecord(upper, uri)) return null;
      final redaction = config.redaction;
      final call = FlutwireCall(
        id: _nextId(),
        method: upper,
        uri: redaction.applyToUri(uri),
        source: source,
        startedAt: now(),
        request: FlutwireRequest(
          headers: redaction.applyToHeaders(requestHeaders),
          body: FlutwireBody.empty(),
        ),
      );
      if (source == FlutwireSource.io) _noteIoCall(call);
      return FlutwireCallRecorder(this, call);
    } on Object catch (error, stack) {
      internalError(error, stack);
      return null;
    }
  }

  bool _shouldRecord(String upperMethod, Uri uri) {
    if (!config.isActive || paused.value) return false;
    for (final rule in config.ignore) {
      if (rule.matches(upperMethod, uri)) return false;
    }
    return true;
  }

  void _noteIoCall(FlutwireCall call) {
    _recentIo.add(_Began(call.method, call.uri, call.startedAt));
    if (_recentIo.length > _recentIoLimit) _recentIo.removeAt(0);
  }

  /// Starts watching a call that a client adapter is about to stand down for,
  /// because the `dart:io` capture is meant to record it. Returns null when
  /// there is nothing to watch: the capture is not installed, or the call is
  /// one Flutwire does not record, such as an ignored one.
  ///
  /// The adapter calls [FlutwireStandDown.finish] once the call is over. If the
  /// capture never saw it, the inspector says so.
  FlutwireStandDown? watchStandDown({
    required String method,
    required Uri uri,
    required String client,
  }) {
    try {
      final upper = method.toUpperCase();
      if (!wireCaptureActive || !_shouldRecord(upper, uri)) return null;
      return FlutwireStandDown._(
        this,
        upper,
        config.redaction.applyToUri(uri),
        client,
        now(),
      );
    } on Object catch (error, stack) {
      internalError(error, stack);
      return null;
    }
  }

  void _finishStandDown(FlutwireStandDown watch) {
    try {
      for (final seen in _recentIo.reversed) {
        if (seen.startedAt.isBefore(watch.startedAt)) break;
        if (seen.method == watch.method && seen.uri == watch.uri) return;
      }
      // Without the capture there is nothing to blame the client for.
      if (!verifyCapture()) return;
      coverage.report(
        FlutwireGap.clientBypassesDartIo,
        '${watch.client} · ${watch.uri.host}',
        now(),
      );
    } on Object catch (error, stack) {
      internalError(error, stack);
    }
  }

  /// Checks that the `dart:io` capture would still see a call, and records a
  /// note when something replaced it. Returns whether it would.
  bool verifyCapture() {
    final probe = wireCaptureProbe;
    if (!wireCaptureActive || probe == null) return true;
    final bool intact;
    try {
      intact = probe();
    } on Object {
      return true;
    }
    if (intact) {
      coverage.resolve(FlutwireGap.captureReplaced);
    } else {
      coverage.report(FlutwireGap.captureReplaced, 'HttpOverrides', now());
    }
    return intact;
  }

  @override
  void publish(FlutwireCall call, {required bool finished}) => store.put(call);

  @override
  void internalError(Object error, StackTrace stack) {
    internalErrorCount++;
    if (_reportedInternalError) return;
    _reportedInternalError = true;
    reportProblem(
      'A call could not be recorded and was skipped.',
      error: error,
      stack: stack,
    );
  }

  /// Releases the store and the listeners.
  Future<void> dispose() async {
    paused.dispose();
    coverage.dispose();
    await store.dispose();
  }

  int _nextId() {
    final micros = _clock().microsecondsSinceEpoch;
    _lastId = micros > _lastId ? micros : _lastId + 1;
    return _lastId;
  }

  static const int _recentIoLimit = 64;
}

/// A call the `dart:io` capture began.
final class _Began {
  const _Began(this.method, this.uri, this.startedAt);

  final String method;
  final Uri uri;
  final DateTime startedAt;
}

/// A call a client adapter stood down for, watched until it is over.
///
/// Adapters hold one while the call runs and call [finish] at the end, whatever
/// the outcome. Flutwire then looks for the same call among those the
/// `dart:io` capture recorded.
final class FlutwireStandDown {
  FlutwireStandDown._(
    this._engine,
    this.method,
    this.uri,
    this.client,
    this.startedAt,
  );

  final FlutwireEngine _engine;

  /// The method of the call, in upper case.
  final String method;

  /// The address of the call, as the inspector shows it.
  final Uri uri;

  /// What stood down, for the note: the adapter and the client it wraps.
  final String client;

  /// When the adapter stood down.
  final DateTime startedAt;

  /// Says that the call is over.
  void finish() => _engine._finishStandDown(this);
}
