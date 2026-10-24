import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../config.dart';
import '../diagnostics.dart';
import '../model/call.dart';
import '../model/message.dart';
import 'preferences_io.dart';
import 'store.dart';

/// A store that keeps the history on disk, so it survives a restart and a
/// notification can open it after the app was killed.
///
/// Layout, under the folder it is given:
///
/// ```
/// layout              the number of this layout, which is [currentLayout]
/// calls/<id>.json     the summary of a call: headers, status, timings
/// bodies/<id>.req     the request body bytes that were kept
/// bodies/<id>.res     the response body bytes that were kept
/// messages/<id>.jsonl the messages of a WebSocket or an event stream, a line each
/// preferences.json    what the user picked in the settings
/// ```
///
/// A folder with no `layout` file is new, or was written by a release from
/// before the file existed, whose layout is the first. A folder whose layout is
/// newer than this release knows is not opened at all, so that a release never
/// reads another's files wrongly or sweeps away what it cannot read.
///
/// A call is written when it ends, bodies and messages first and summary last,
/// through a temporary file, so a summary on disk always has its bodies and a
/// crash leaves at worst an orphan body, which the next start sweeps away.
/// Summaries stay in memory; bodies and messages are read back when a call is
/// opened, and released again when memory runs short.
final class DiskFlutwireStore extends MemoryFlutwireStore {
  DiskFlutwireStore._(
    Directory root,
    this._config,
    this._now,
    this._preferences, {
    super.notifyInterval,
  }) : _calls = Directory('${root.path}/calls'),
       _bodies = Directory('${root.path}/bodies'),
       _messages = Directory('${root.path}/messages'),
       super(
         maxCalls: _config.maxCalls,
         maxBytes: _config.maxMemoryBytes,
         preferences: _preferences,
       );

  /// The layout this release writes, and the newest one it reads.
  static const int currentLayout = 1;

  /// Opens the history stored under [root], creating it if needed, and applies
  /// the retention policy and the limits to what it finds.
  ///
  /// Throws a [FormatException] when the folder has a layout this release does
  /// not know, and leaves what is in it as it is.
  static Future<DiskFlutwireStore> open(
    Directory root,
    FlutwireConfig config, {
    DateTime Function()? clock,
    Duration notifyInterval = const Duration(milliseconds: 120),
  }) async {
    await _checkLayout(root);
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
  final Directory _messages;

  /// Ids whose files are complete on disk, which is what makes it safe to let
  /// go of their bodies in memory.
  final Set<int> _persisted = {};
  Future<void> _queue = Future.value();
  DateTime? _lastSweep;

  /// Completes when every write and delete asked for so far has finished.
  Future<void> get settled => _queue;

  /// Records the layout in a folder that has none, and refuses a folder whose
  /// layout is one this release cannot read.
  static Future<void> _checkLayout(Directory root) async {
    await root.create(recursive: true);
    final file = File('${root.path}/layout');
    final String text;
    try {
      text = (await file.readAsString()).trim();
    } on PathNotFoundException {
      await file.writeAsString('$currentLayout\n', flush: true);
      return;
    }
    final found = int.tryParse(text);
    if (found == null || found < 1 || found > currentLayout) {
      throw FormatException(
        'The history in ${root.path} has the layout "$text", and this '
        'release reads layout $currentLayout. It was left as it is.',
      );
    }
  }

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
    return call.copyWith(
      request: call.request.copyWith(body: call.request.body.unload()),
      response: response?.copyWith(body: response.body.unload()),
      messages: call.messages?.unload(),
    );
  }

  @override
  Future<FlutwireCall?> load(int id) async {
    final call = find(id);
    if (call == null) return null;
    final response = call.response;
    final messages = call.messages;
    if (call.request.body.loaded &&
        (response?.body.loaded ?? true) &&
        (messages?.loaded ?? true)) {
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
        messages: messages == null || messages.loaded
            ? messages
            : messages.withItems(await _readMessages(id)),
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
    try {
      return await File('${_bodies.path}/$name').readAsBytes();
    } on PathNotFoundException {
      return Uint8List(0);
    }
  }

  Future<List<FlutwireMessage>> _readMessages(int id) async {
    final List<String> lines;
    try {
      lines = await File('${_messages.path}/$id.jsonl').readAsLines();
    } on PathNotFoundException {
      return const [];
    }
    return [for (final line in lines) ?_message(line)];
  }

  /// The message a line of a messages file holds, or null for a line that is
  /// damaged, which a crash in the middle of a write can leave.
  static FlutwireMessage? _message(String line) {
    try {
      return FlutwireMessage.fromJson(jsonDecode(line) as Map<String, Object?>);
    } on Object {
      return null;
    }
  }

  void _enqueue(Future<void> Function() task) {
    _queue = _queue.then((_) => task()).catchError((
      Object error,
      StackTrace stack,
    ) {
      reportProblem(
        'Could not update the history on disk.',
        error: error,
        stack: stack,
      );
    });
  }

  Future<void> _write(FlutwireCall call) async {
    await _bodies.create(recursive: true);
    await _messages.create(recursive: true);
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
    final messages = call.messages;
    if (messages != null && messages.loaded && messages.items.isNotEmpty) {
      await File('${_messages.path}/$id.jsonl').writeAsString(
        messages.items.map((m) => jsonEncode(m.toJson())).join('\n'),
      );
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
        '${_messages.path}/$id.jsonl',
      ]) {
        try {
          await File(path).delete();
        } on PathNotFoundException {
          // Already gone, which is what was asked for.
        }
      }
    }
  }

  Future<void> _load() async {
    await _calls.create(recursive: true);
    await _bodies.create(recursive: true);
    await _messages.create(recursive: true);
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
    // Bodies and messages whose summary never made it to disk.
    for (final directory in [_bodies, _messages]) {
      await for (final entity in directory.list()) {
        if (entity is! File) continue;
        final id = int.tryParse(entity.uri.pathSegments.last.split('.').first);
        if (id == null || !known.contains(id)) await entity.delete();
      }
    }
    _persisted.addAll(known);
    seed(loaded);
    await _sweep();
  }

  Future<void> _maybeSweep() async {
    final last = _lastSweep;
    if (last != null && _now().difference(last) < const Duration(minutes: 10)) {
      return;
    }
    await _sweep();
  }

  /// Applies the retention period and the disk budget. Pinned calls stay.
  Future<void> _sweep() async {
    _lastSweep = _now();
    final period = _config.retention.period;
    final cutoff = period == null ? null : _now().subtract(period);
    final doomed = <int>{};
    final survivors = <FlutwireCall>[];
    for (final call in held) {
      if (cutoff != null && !call.pinned && call.startedAt.isBefore(cutoff)) {
        doomed.add(call.id);
      } else {
        survivors.add(call);
      }
    }
    // Over budget, the oldest calls go first.
    survivors.sort((a, b) => a.id.compareTo(b.id));
    var disk = survivors.fold(0, (sum, call) => sum + _diskBytes(call));
    for (final call in survivors) {
      if (disk <= _config.maxDiskBytes) break;
      if (call.pinned) continue;
      doomed.add(call.id);
      disk -= _diskBytes(call);
    }
    if (doomed.isNotEmpty) await remove(doomed);
  }

  static int _diskBytes(FlutwireCall call) =>
      call.request.body.keptBytes +
      (call.response?.body.keptBytes ?? 0) +
      (call.messages?.keptBytes ?? 0);
}
