import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../config.dart';
import '../l10n/lookup.dart';
import '../model/call.dart';
import '../platform/native.dart';
import '../store/store.dart';
import '../util/format.dart';

/// Keeps the notification in the shade in step with the history.
///
/// The notification lists the newest calls, one per line, and carries a
/// button that clears the history. Updates are folded together so a burst of
/// calls does not flood the notification manager, the notification is
/// withdrawn while the inspector is on screen, and nothing is posted until the
/// platform has said the app may.
final class FlutwireNotifier with WidgetsBindingObserver {
  /// Creates a notifier. Call [start] to begin.
  FlutwireNotifier({
    required FlutwireNative native,
    required FlutwireStore store,
    required FlutwireNotificationConfig config,
    required ValueListenable<bool> inspectorOpen,
    required Locale? Function() locale,
  }) : _native = native,
       _store = store,
       _config = config,
       _inspectorOpen = inspectorOpen,
       _locale = locale;

  final FlutwireNative _native;
  final FlutwireStore _store;
  final FlutwireNotificationConfig _config;
  final ValueListenable<bool> _inspectorOpen;
  final Locale? Function() _locale;

  final ValueNotifier<FlutwireNotificationPermission> _permission =
      ValueNotifier(FlutwireNotificationPermission.notDetermined);
  Timer? _quiet;
  bool _dirty = false;
  bool _running = false;
  bool _rerun = false;
  bool _started = false;
  bool _disposed = false;
  bool _askedOnce = false;
  bool _posted = false;
  String? _lastSignature;

  /// Whether the user has allowed notifications, as far as is known.
  ValueListenable<FlutwireNotificationPermission> get permission => _permission;

  /// Begins following the history.
  void start({FlutwireNotificationPermission? known}) {
    if (_started || _disposed) return;
    _started = true;
    if (known != null) _permission.value = known;
    _store.calls.addListener(_changed);
    _inspectorOpen.addListener(_changed);
    WidgetsBinding.instance.addObserver(this);
    _changed();
  }

  /// Asks the user for permission now, from a button, and updates the
  /// notification if they agree.
  Future<FlutwireNotificationPermission> requestPermission() async {
    _askedOnce = true;
    final answer = await _native.requestPermission();
    _permission.value = answer;
    _lastSignature = null;
    _changed();
    return answer;
  }

  /// Opens the system page where notifications can be allowed.
  Future<void> openSettings() => _native.openNotificationSettings();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The user may have switched notifications on in the system settings.
    if (state != AppLifecycleState.resumed) return;
    unawaited(_refreshPermission());
  }

  Future<void> _refreshPermission() async {
    final now = await _native.permission();
    if (now == _permission.value) return;
    _permission.value = now;
    _lastSignature = null;
    _changed();
  }

  void _changed() {
    if (_disposed) return;
    if (_quiet != null) {
      _dirty = true;
      return;
    }
    _kick();
    _quiet = Timer(_config.throttle, () {
      _quiet = null;
      if (_dirty) {
        _dirty = false;
        _changed();
      }
    });
  }

  /// Runs updates one at a time. Asking for permission can take as long as the
  /// user likes, and the history keeps changing meanwhile, so a change that
  /// arrives during an update schedules another once it is over.
  void _kick() {
    if (_running) {
      _rerun = true;
      return;
    }
    _running = true;
    unawaited(_loop());
  }

  Future<void> _loop() async {
    try {
      do {
        _rerun = false;
        await _update();
      } while (_rerun && !_disposed);
    } finally {
      _running = false;
    }
  }

  Future<void> _update() async {
    if (_disposed || !_config.enabled) return;
    if (_store.calls.value.isEmpty ||
        (_config.hideWhileInspectorOpen && _inspectorOpen.value)) {
      await _withdraw();
      return;
    }
    if (!await _mayPost()) {
      await _withdraw();
      return;
    }
    // Read only now: the history may have moved on while permission was asked.
    final calls = _store.calls.value;
    if (calls.isEmpty) return;
    final strings = stringsFor(_locale());
    final shown = calls.take(_config.lines).map(callLine).toList();
    final failed = calls.where((c) => c.isError).length;
    final summary = strings.summary(calls: calls.length, failed: failed);
    final signature =
        '${strings.notificationTitle}\n$summary\n${shown.join('\n')}';
    if (signature == _lastSignature) return;
    _lastSignature = signature;
    _posted = true;
    await _native.showSummary(
      title: strings.notificationTitle,
      lines: shown,
      summary: summary,
      count: calls.length,
      clearLabel: strings.clear,
    );
  }

  Future<bool> _mayPost() async {
    if (_native.isMissing) return false;
    if (_permission.value == FlutwireNotificationPermission.granted) {
      return true;
    }
    if (_permission.value == FlutwireNotificationPermission.notDetermined) {
      final current = await _native.permission();
      _permission.value = current;
      if (current == FlutwireNotificationPermission.granted) return true;
      if (current == FlutwireNotificationPermission.notDetermined &&
          _config.requestPermission &&
          !_askedOnce) {
        _askedOnce = true;
        final answer = await _native.requestPermission();
        _permission.value = answer;
        return answer == FlutwireNotificationPermission.granted;
      }
    }
    return false;
  }

  Future<void> _withdraw() async {
    if (!_posted) return;
    _posted = false;
    _lastSignature = null;
    await _native.cancelSummary();
  }

  /// Stops following the history and withdraws the notification.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _quiet?.cancel();
    if (_started) {
      _store.calls.removeListener(_changed);
      _inspectorOpen.removeListener(_changed);
      WidgetsBinding.instance.removeObserver(this);
    }
    if (_posted) await _native.cancelSummary();
    _permission.dispose();
  }
}

/// The line that stands for [call] in the notification: its status, method,
/// host and path, and how long it took once it is over. A GraphQL call is named
/// by its operation instead.
String callLine(FlutwireCall call) {
  final status = switch (call.state) {
    FlutwireCallState.pending => '···',
    FlutwireCallState.failed => 'ERR',
    FlutwireCallState.cancelled => 'CXL',
    FlutwireCallState.completed => '${call.statusCode ?? '---'}',
  };
  final path = call.uri.path.isEmpty ? '/' : call.uri.path;
  final what =
      call.graphql?.operationName ??
      '${call.host}$path${call.uri.hasQuery ? '?…' : ''}';
  final shortened = what.length > 52 ? '${what.substring(0, 51)}…' : what;
  final took = call.isPending ? '' : ' · ${formatDuration(call.duration)}';
  return '$status ${call.method} $shortened$took';
}
