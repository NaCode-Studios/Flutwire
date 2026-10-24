import 'dart:isolate';
import 'dart:ui' show IsolateNameServer;

import 'package:flutter/foundation.dart';

import 'model/call.dart';

/// The name the main isolate registers its port under, so another isolate can
/// find it without being handed anything.
const String _portName = 'it.nacodestudios.flutwire.isolates';

/// How an isolate with no recorder tells the main isolate that a Flutwire
/// adapter ran in it.
///
/// `HttpOverrides` belong to one isolate, so a call made with `Isolate.run` or
/// `compute` is invisible to the capture of the main isolate. All Flutwire can
/// do about it is say so: the main isolate listens on a named port, and an
/// adapter that finds itself in an isolate with no recorder writes to it.
final class FlutwireIsolateBridge {
  FlutwireIsolateBridge._(this._port);

  /// Starts listening, and returns null where there is nothing to listen with.
  /// [onGap] gets what the other isolates report.
  static FlutwireIsolateBridge? listen(void Function(String subject) onGap) {
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
      port.listen((Object? message) {
        if (message is String) onGap(message);
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
