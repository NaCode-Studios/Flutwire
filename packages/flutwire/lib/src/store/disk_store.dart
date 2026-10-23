import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

import '../config.dart';
import '../model/call.dart';
import 'preferences_io.dart';
import 'store.dart';

/// A store that keeps the history on disk, so it survives a restart and a
/// notification can open it after the app was killed.
///
/// Layout, under the folder it is given:
///
/// ```
/// calls/<id>.json     the summary of a call: headers, status, timings
/// bodies/<id>.req     the request body bytes that were kept
/// bodies/<id>.res     the response body bytes that were kept
/// preferences.json    what the user picked in the settings
/// ```
///
/// A call is written when it ends, bodies first and summary last, through a
/// temporary file, so a summary on disk always has its bodies and a crash
/// leaves at worst an orphan body, which the next start sweeps away. Summaries
/// stay in memory; bodies are read back when a call is opened, and released
/// again when memory runs short.
final class DiskFlutwireStore extends MemoryFlutwireStore {
  DiskFlutwireStore._(
    Directory root,
    this._config,
    this._now,
    this._preferences, {
    super.notifyInterval,
  }) : _calls = Directory('${root.path}/calls'),
       _bodies = Directory('${root.path}/bodies'),
       super(
         maxCalls: _config.maxCalls,
         maxBytes: _config.maxMemoryBytes,
         preferences: _preferences,
       );

  /// Opens the history stored under [root], creating it if needed, and applies
  /// the retention policy and the limits to what it finds.
  static Future<DiskFlutwireStore> open(
    Directory root,
    FlutwireConfig config, {
    DateTime Function()? clock,
    Duration notifyInterval = const Duration(milliseconds: 120),
  }) async {
    final store = DiskFlutwireStore._(
      root,
      config,
      clock ?? DateTime.now,
      await FileFlutwirePreferences.open(root),
      notifyInterval: notifyInterval,
    );
    await store._load();
    return store;
  }

  final FlutwireConfig _config;
  final DateTime Function() _now;
  final FileFlutwirePreferences _preferences;
  final Directory _calls;
  final Directory _bodies;

  /// Ids whose files are complete on disk, which is what makes it safe to let
  /// go of their bodies in memory.
  final Set<int> _persisted = {};
  Future<void> _queue = Future.value();
  DateTime? _lastSweep;

  /// Completes when every write and delete asked for so far has finished.
  Future<void> get settled => _queue;

  @override
  void onPut(FlutwireCall call) {
    if (call.isPending) return;
    _enqueue(() => _write(call));
  }

  @override
  void onEvicted(FlutwireCall call) => _enqueue(() => _delete([call.id]));

  @override
  void onRemoved(Iterable<FlutwireCall> calls) {
    final ids = [for (final c in calls) c.id];
    _enqueue(() => _delete(ids));
  }

  @override
  FlutwireCall? releaseBodies(FlutwireCall call) {
    if (!_persisted.contains(call.id)) return null;
    final response = call.response;
    return FlutwireCall(
      id: call.id,
      method: call.method,
      uri: call.uri,
      source: call.source,
      state: call.state,
      startedAt: call.startedAt,
      firstByteAt: call.firstByteAt,
      endedAt: call.endedAt,
      request: call.request.copyWith(body: call.request.body.unload()),
      response: response?.copyWith(body: response.body.unload()),
      error: call.error,
      graphql: call.graphql,
      pinned: call.pinned,
    );
  }

  @override
  Future<FlutwireCall?> load(int id) async {
    final call = find(id);
    if (call == null) return null;
    final response = call.response;
    if (call.request.body.loaded && (response?.body.loaded ?? true)) {
      return call;
    }
    await _queue;
    try {
      final request = call.request.body.loaded
          ? call.request.body
          : call.request.body.withBytes(await _read('$id.req'));
      final responseBody = response == null || response.body.loaded
          ? response?.body
          : response.body.withBytes(await _read('$id.res'));
      return call.copyWith(
        request: call.request.copyWith(body: request),
        response: response?.copyWith(body: responseBody),
      );
    } on FileSystemException {
      return call;
    }
  }

  @override
  Future<void> dispose() async {
    await _queue;
    await _preferences.settled;
    await super.dispose();
  }

  Future<Uint8List> _read(String name) async {
    final file = File('${_bodies.path}/$name');
    if (!await file.exists()) return Uint8List(0);
    return file.readAsBytes();
  }

  void _enqueue(Future<void> Function() task) {
    _queue = _queue.then((_) => task()).catchError((Object error) {
      debugPrint('Flutwire: could not update the history on disk: $error');
    });
  }

  Future<void> _write(FlutwireCall call) async {
    await _bodies.create(recursive: true);
    await _calls.create(recursive: true);
    final id = call.id;
    final request = call.request.body;
    if (request.loaded && request.bytes.isNotEmpty) {
      await File('${_bodies.path}/$id.req').writeAsBytes(request.bytes);
    }
    final response = call.response?.body;
    if (response != null && response.loaded && response.bytes.isNotEmpty) {
      await File('${_bodies.path}/$id.res').writeAsBytes(response.bytes);
    }
    final temporary = File('${_calls.path}/$id.json.tmp');
    await temporary.writeAsString(jsonEncode(call.toJson()), flush: true);
    await temporary.rename('${_calls.path}/$id.json');
    _persisted.add(id);
    await _maybeSweep();
  }

  Future<void> _delete(Iterable<int> ids) async {
    for (final id in ids) {
      _persisted.remove(id);
      for (final path in [
        '${_calls.path}/$id.json',
        '${_calls.path}/$id.json.tmp',
        '${_bodies.path}/$id.req',
        '${_bodies.path}/$id.res',
      ]) {
        final file = File(path);
        if (await file.exists()) await file.delete();
      }
    }
  }

  Future<void> _load() async {
    await _calls.create(recursive: true);
    await _bodies.create(recursive: true);
    final loaded = <FlutwireCall>[];
    final known = <int>{};
    await for (final entity in _calls.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (name.endsWith('.tmp')) {
        await entity.delete();
        continue;
      }
      if (!name.endsWith('.json')) continue;
      try {
        final json =
            jsonDecode(await entity.readAsString()) as Map<String, Object?>;
        var call = FlutwireCall.fromJson(json);
        if (call.isPending) {
          call = call.copyWith(state: FlutwireCallState.cancelled);
        }
        loaded.add(call);
        known.add(call.id);
      } on Object {
        // A summary that cannot be read is worth nothing; take it out.
        await entity.delete();
      }
    }
    // Bodies whose summary never made it to disk.
    await for (final entity in _bodies.list()) {
      if (entity is! File) continue;
      final id = int.tryParse(entity.uri.pathSegments.last.split('.').first);
      if (id == null || !known.contains(id)) await entity.delete();
    }
    _persisted.addAll(known);
    seed(loaded);
    await _sweep(force: true);
  }

  Future<void> _maybeSweep() async {
    final last = _lastSweep;
    if (last != null && _now().difference(last) < const Duration(minutes: 10)) {
      return;
    }
    await _sweep(force: true);
  }

  /// Applies the retention period and the disk budget. Pinned calls stay.
  Future<void> _sweep({required bool force}) async {
    _lastSweep = _now();
    final doomed = <int>[];
    final period = _config.retention.period;
    final all = calls.value.isEmpty ? _snapshot() : calls.value;
    if (period != null) {
      final cutoff = _now().subtract(period);
      for (final call in all) {
        if (!call.pinned && call.startedAt.isBefore(cutoff)) {
          doomed.add(call.id);
        }
      }
    }
    var disk = 0;
    final survivors = [
      for (final call in all)
        if (!doomed.contains(call.id)) call,
    ]..sort((a, b) => a.id.compareTo(b.id));
    for (final call in survivors) {
      disk += _diskBytes(call);
    }
    for (final call in survivors) {
      if (disk <= _config.maxDiskBytes) break;
      if (call.pinned) continue;
      doomed.add(call.id);
      disk -= _diskBytes(call);
    }
    if (doomed.isNotEmpty) await remove(doomed);
  }

  List<FlutwireCall> _snapshot() {
    flush();
    return calls.value;
  }

  static int _diskBytes(FlutwireCall call) =>
      call.request.body.keptBytes + (call.response?.body.keptBytes ?? 0);
}
