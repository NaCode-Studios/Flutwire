import 'dart:async';
import 'dart:isolate';
import 'dart:ui' show IsolateNameServer;

import 'package:flutter/foundation.dart';

import 'capture/redaction.dart';
import 'capture/wire/wire.dart';
import 'config.dart';
import 'coverage.dart';
import 'engine.dart';
import 'model/call.dart';

/// The name the main isolate registers its port under, so another isolate can
/// find it without being handed anything.
const String _portName = 'it.nacodestudios.flutwire.isolates';

/// What an isolate that joins the history needs to record the way the main
/// isolate would.
@immutable
final class _Settings {
  const _Settings({
    required this.origin,
    required this.maxBodyBytes,
    required this.redaction,
    required this.captureDartIo,
  });

  /// The number the main isolate gave this isolate.
  final int origin;
  final int maxBodyBytes;
  final FlutwireRedaction redaction;
  final bool captureDartIo;
}

/// An isolate asking the main one for its [_Settings], which it sends to
/// [reply].
@immutable
final class _Attach {
  const _Attach(this.reply);

  final SendPort reply;
}

/// A snapshot of a call that an isolate is recording, for the history of the
/// main isolate.
@immutable
final class _Snapshot {
  const _Snapshot({
    required this.origin,
    required this.call,
    required this.finished,
  });

  final int origin;
  final FlutwireCall call;
  final bool finished;
}

/// How the isolate that keeps the history hears from the others.
///
/// `HttpOverrides` belong to one isolate, so a call made with `Isolate.run` or
/// `compute` is invisible to the capture of the main isolate. The main isolate
/// listens on a named port instead. An isolate that attaches to Flutwire
/// records its own calls and sends each snapshot there, and the main isolate
/// puts them in the history. An adapter that runs in an isolate that did not
/// attach can only say so, and the main isolate turns that into a note.
final class FlutwireIsolateBridge {
  FlutwireIsolateBridge._(this._port);

  /// Starts listening for the other isolates on behalf of [engine], and returns
  /// null where there is nothing to listen with.
  static FlutwireIsolateBridge? listen(FlutwireEngine engine) {
    if (kIsWeb) return null;
    try {
      final port = ReceivePort('flutwire.isolates');
      // A hot restart leaves the old registration behind, and registering over
      // it fails.
      IsolateNameServer.removePortNameMapping(_portName);
      if (!IsolateNameServer.registerPortWithName(port.sendPort, _portName)) {
        port.close();
        return null;
      }
      var origins = 0;
      port.listen((Object? message) {
        try {
          switch (message) {
            case final String subject:
              engine.coverage.report(
                FlutwireGap.otherIsolate,
                subject,
                engine.now(),
              );
            case _Attach(:final reply):
              reply.send(
                _Settings(
                  origin: ++origins,
                  maxBodyBytes: engine.config.maxBodyBytes,
                  redaction: engine.config.redaction,
                  captureDartIo: engine.config.captureDartIo,
                ),
              );
            case _Snapshot(:final origin, :final call, :final finished):
              engine.adopt(call, origin: origin, finished: finished);
          }
        } on Object catch (error, stack) {
          engine.internalError(error, stack);
        }
      });
      return FlutwireIsolateBridge._(port);
    } on Object {
      return null;
    }
  }

  final ReceivePort _port;

  /// Stops listening.
  void close() {
    IsolateNameServer.removePortNameMapping(_portName);
    _port.close();
  }

  static final Set<String> _told = {};

  /// Makes [tell] speak again about what it has already told. For tests.
  @visibleForTesting
  static void forgetTold() => _told.clear();

  /// What a note calls an isolate. `Isolate.run` names its isolate after the
  /// function the VM starts it with, which tells a reader nothing, and `compute`
  /// names it after the callback's `toString`, which can run to a whole line.
  @visibleForTesting
  static String describe(String? debugName) {
    final name = debugName?.trim() ?? '';
    if (name.isEmpty) return 'an isolate';
    if (name == '_RemoteRunner._remoteExecute') return 'Isolate.run';
    return name.length <= 48 ? name : '${name.substring(0, 47)}…';
  }

  /// Said from an isolate that has no recorder: the adapter for [source] ran
  /// here. Tells the main isolate once per source and isolate, and does
  /// nothing when the main isolate is not listening.
  static void tell(FlutwireSource source) {
    if (kIsWeb) return;
    final subject = '${source.label} in ${describe(Isolate.current.debugName)}';
    if (!_told.add(subject)) return;
    try {
      IsolateNameServer.lookupPortByName(_portName)?.send(subject);
    } on Object {
      // There is nobody to tell, and the call goes on regardless.
    }
  }
}

/// The connection from an isolate other than the main one to the history of
/// the main isolate.
///
/// While an isolate is attached it records its own calls, with the redaction
/// and the size limit the main isolate uses, and sends them over. The state is
/// per isolate, like `HttpOverrides`, which is why every isolate has to attach
/// for itself.
final class FlutwireIsolateLink {
  FlutwireIsolateLink._(this._engine, this._uninstall);

  static FlutwireIsolateLink? _current;
  static Future<FlutwireIsolateLink?>? _connecting;

  /// How long to wait for the main isolate to answer. It answers as soon as it
  /// has a turn, so a long wait means it is not there.
  static const Duration _answerWithin = Duration(seconds: 2);

  final FlutwireEngine _engine;
  final void Function() _uninstall;

  /// The engine that records in this isolate, or null while it is not attached.
  static FlutwireEngine? get engine => _current?._engine;

  /// Joins the history of the main isolate. Does nothing where there is no
  /// history to join: the main isolate is not recording, or Flutwire did not
  /// start in it. It never throws.
  static Future<void> attach() async {
    if (kIsWeb || _current != null) return;
    final connecting = _connecting ??= _connect();
    try {
      _current ??= await connecting;
    } finally {
      _connecting = null;
    }
  }

  /// Leaves the history again. Calls still in flight keep reporting to it.
  static Future<void> detach() async {
    final link = _current;
    _current = null;
    if (link == null) return;
    link._uninstall();
    await link._engine.dispose();
  }

  static Future<FlutwireIsolateLink?> _connect() async {
    final reply = ReceivePort('flutwire.attach');
    try {
      final main = IsolateNameServer.lookupPortByName(_portName);
      if (main == null) return null;
      main.send(_Attach(reply.sendPort));
      final answer = await reply.first.timeout(_answerWithin);
      if (answer is! _Settings) return null;
      final engine = FlutwireEngine.forwarding(
        // Recording is on because the isolate that keeps the history is
        // recording: it is the one that answered.
        config: FlutwireConfig(
          enabled: true,
          allowInRelease: true,
          captureDartIo: answer.captureDartIo,
          maxBodyBytes: answer.maxBodyBytes,
          persist: false,
          redaction: answer.redaction,
          notification: const FlutwireNotificationConfig(enabled: false),
          shortcut: false,
        ),
        forward: (call, {required finished}) => main.send(
          _Snapshot(origin: answer.origin, call: call, finished: finished),
        ),
      );
      return FlutwireIsolateLink._(
        engine,
        answer.captureDartIo ? installWireCapture(engine) : () {},
      );
    } on Object {
      return null;
    } finally {
      reply.close();
    }
  }
}
