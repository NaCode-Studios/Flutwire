import 'dart:async';

import 'package:flutter/foundation.dart';

import '../model/call.dart';
import 'preferences.dart';

/// Where recorded calls are kept.
///
/// The inspector and the notification read from a store, and the recorders
/// write to it. A store is a plain object, so tests and apps can substitute
/// their own.
abstract interface class FlutwireStore {
  /// The history, newest first.
  ///
  /// A new list is published when the history changes, and changes that arrive
  /// in quick succession are folded into one notification so that a busy
  /// connection does not rebuild a screen for every chunk it reads.
  ValueListenable<List<FlutwireCall>> get calls;

  /// What the user picked in the inspector's settings, kept next to the
  /// history. Clearing the history leaves it alone.
  FlutwirePreferences get preferences;

  /// The call with [id], or null. Its bodies may not be loaded; see [load].
  FlutwireCall? find(int id);

  /// The call with [id] with its bodies read in, or null if it is gone.
  Future<FlutwireCall?> load(int id);

  /// Adds [call], or replaces the call with the same id.
  void put(FlutwireCall call);

  /// Removes the calls with [ids].
  Future<void> remove(Iterable<int> ids);

  /// Removes every call, except the pinned ones when [keepPinned] is true.
  Future<void> clear({bool keepPinned = true});

  /// Pins or unpins the calls with [ids]. A pinned call survives clearing,
  /// retention and the limits.
  Future<void> setPinned(Iterable<int> ids, {required bool pinned});

  /// Releases the resources held by the store.
  Future<void> dispose();
}

/// A store that keeps the history in memory only.
///
/// It enforces the call limit and the memory budget by dropping the oldest
/// calls that are not pinned. [DiskFlutwireStore] builds on it.
class MemoryFlutwireStore implements FlutwireStore {
  /// Creates an empty store.
  MemoryFlutwireStore({
    this.maxCalls = 500,
    this.maxBytes = 32 * 1024 * 1024,
    this.notifyInterval = const Duration(milliseconds: 120),
    FlutwirePreferences? preferences,
  }) : preferences = preferences ?? MemoryFlutwirePreferences();

  @override
  final FlutwirePreferences preferences;

  /// The most calls kept.
  final int maxCalls;

  /// The most body bytes kept in memory.
  final int maxBytes;

  /// The shortest time between two notifications to listeners.
  final Duration notifyInterval;

  final Map<int, FlutwireCall> _byId = {};
  final ValueNotifier<List<FlutwireCall>> _notifier = ValueNotifier(const []);
  Timer? _timer;
  bool _dirty = false;
  bool _disposed = false;
  int _bytes = 0;

  /// Called after [call] was dropped to respect a limit, so a subclass can
  /// remove what it keeps elsewhere.
  @protected
  void onEvicted(FlutwireCall call) {}

  /// Called after a call was added or replaced.
  @protected
  void onPut(FlutwireCall call) {}

  /// Called after a call was removed on request.
  @protected
  void onRemoved(Iterable<FlutwireCall> calls) {}

  /// Lets go of the bodies of [call] to free memory and returns what to keep
  /// in its place, or null if the call cannot be kept without them, in which
  /// case it is dropped. A store that has the bodies somewhere else, such as
  /// on disk, overrides this.
  @protected
  FlutwireCall? releaseBodies(FlutwireCall call) => null;

  /// Adds [calls] that already exist elsewhere, such as ones read from disk,
  /// without telling [onPut] about them.
  @protected
  void seed(Iterable<FlutwireCall> calls) {
    for (final call in calls) {
      final previous = _byId[call.id];
      if (previous != null) _bytes -= _sizeOf(previous);
      _byId[call.id] = call;
      _bytes += _sizeOf(call);
    }
    _enforceLimits(keep: -1);
    _markDirty();
  }

  @override
  ValueListenable<List<FlutwireCall>> get calls => _notifier;

  /// The number of calls held.
  int get length => _byId.length;

  /// The body bytes held in memory.
  int get memoryBytes => _bytes;

  @override
  FlutwireCall? find(int id) => _byId[id];

  @override
  Future<FlutwireCall?> load(int id) async => _byId[id];

  @override
  void put(FlutwireCall call) {
    if (_disposed) return;
    final previous = _byId[call.id];
    if (previous != null) _bytes -= _sizeOf(previous);
    _byId[call.id] = call;
    _bytes += _sizeOf(call);
    onPut(call);
    _enforceLimits(keep: call.id);
    _markDirty();
  }

  @override
  Future<void> remove(Iterable<int> ids) async {
    final removed = <FlutwireCall>[];
    for (final id in ids) {
      final call = _byId.remove(id);
      if (call != null) {
        _bytes -= _sizeOf(call);
        removed.add(call);
      }
    }
    if (removed.isEmpty) return;
    onRemoved(removed);
    _markDirty();
  }

  @override
  Future<void> clear({bool keepPinned = true}) async {
    final doomed = [
      for (final call in _byId.values)
        if (!(keepPinned && call.pinned)) call,
    ];
    await remove(doomed.map((c) => c.id));
  }

  @override
  Future<void> setPinned(Iterable<int> ids, {required bool pinned}) async {
    var changed = false;
    for (final id in ids) {
      final call = _byId[id];
      if (call == null || call.pinned == pinned) continue;
      final updated = call.copyWith(pinned: pinned);
      _byId[id] = updated;
      onPut(updated);
      changed = true;
    }
    if (changed) _markDirty();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _notifier.dispose();
  }

  /// Publishes the current history now, without waiting for the interval.
  void flush() {
    _timer?.cancel();
    _timer = null;
    _publish();
  }

  void _markDirty() {
    _dirty = true;
    if (_timer != null || _disposed) return;
    if (notifyInterval == Duration.zero) {
      _timer = Timer(Duration.zero, flush);
      return;
    }
    // Leading edge: the first change after a quiet spell is shown at once.
    _publish();
    _timer = Timer(notifyInterval, () {
      _timer = null;
      if (_dirty) flush();
    });
  }

  void _publish() {
    if (_disposed) return;
    _dirty = false;
    final sorted = _byId.values.toList()..sort((a, b) => b.id.compareTo(a.id));
    _notifier.value = List.unmodifiable(sorted);
  }

  void _enforceLimits({required int keep}) {
    if (_byId.length <= maxCalls && _bytes <= maxBytes) return;
    final oldestFirst = _byId.values.toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    // The call count is a hard limit: the oldest calls that are not pinned go.
    for (final call in oldestFirst) {
      if (_byId.length <= maxCalls) break;
      if (call.pinned || call.id == keep) continue;
      _byId.remove(call.id);
      _bytes -= _sizeOf(call);
      onEvicted(call);
    }
    // Memory is softer: bodies are released first, and a call goes only if it
    // cannot live without them.
    for (final call in oldestFirst) {
      if (_bytes <= maxBytes) break;
      if (call.id == keep || !_byId.containsKey(call.id)) continue;
      if (_sizeOf(call) == 0) continue;
      final replacement = releaseBodies(call);
      if (replacement != null) {
        _bytes -= _sizeOf(call);
        _byId[call.id] = replacement;
        _bytes += _sizeOf(replacement);
      } else if (!call.pinned) {
        _byId.remove(call.id);
        _bytes -= _sizeOf(call);
        onEvicted(call);
      }
    }
  }

  static int _sizeOf(FlutwireCall call) =>
      call.request.body.bytes.length + (call.response?.body.bytes.length ?? 0);
}
