import 'package:flutter/foundation.dart';

import 'capture/recorder.dart';
import 'config.dart';
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
      if (!config.isActive || paused.value) return null;
      final upper = method.toUpperCase();
      for (final rule in config.ignore) {
        if (rule.matches(upper, uri)) return null;
      }
      final redaction = config.redaction;
      return FlutwireCallRecorder(
        this,
        FlutwireCall(
          id: _nextId(),
          method: upper,
          uri: redaction.applyToUri(uri),
          source: source,
          startedAt: now(),
          request: FlutwireRequest(
            headers: redaction.applyToHeaders(requestHeaders),
            body: FlutwireBody.empty(),
          ),
        ),
      );
    } on Object catch (error, stack) {
      internalError(error, stack);
      return null;
    }
  }

  @override
  void publish(FlutwireCall call, {required bool finished}) => store.put(call);

  @override
  void internalError(Object error, StackTrace stack) {
    internalErrorCount++;
    if (_reportedInternalError) return;
    _reportedInternalError = true;
    debugPrint(
      'Flutwire: a call could not be recorded and was skipped: $error',
    );
  }

  /// Releases the store and the listeners.
  Future<void> dispose() async {
    paused.dispose();
    await store.dispose();
  }

  int _nextId() {
    final micros = _clock().microsecondsSinceEpoch;
    _lastId = micros > _lastId ? micros : _lastId + 1;
    return _lastId;
  }
}
