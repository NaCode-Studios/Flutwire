import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutwire/flutwire.dart';
import 'package:flutwire/src/platform/native.dart';
import 'package:flutwire/src/session.dart';
import 'package:flutwire/src/share.dart';

/// The configuration most screen tests run under: recording, nothing native
/// and nothing on disk.
const quietConfig = FlutwireConfig(
  enabled: true,
  captureDartIo: false,
  persist: false,
  shortcut: false,
  locale: Locale('en'),
  notification: FlutwireNotificationConfig(enabled: false),
);

/// A session over a memory store with nothing native behind it, which also
/// remembers what the screens asked of it.
class FakeSession implements FlutwireSession {
  /// Creates a session whose history already holds [calls].
  FakeSession({
    this.config = quietConfig,
    List<FlutwireCall> calls = const [],
    ThemeMode themeMode = ThemeMode.dark,
    FlutwireNotificationPermission permission =
        FlutwireNotificationPermission.unsupported,
  }) : _themeMode = ValueNotifier(themeMode),
       _permission = ValueNotifier(permission) {
    // Oldest first, so the newest ends up on top.
    for (final call in calls.reversed) {
      store.put(call);
    }
    store.flush();
  }

  @override
  final FlutwireConfig config;

  @override
  final MemoryFlutwireStore store = MemoryFlutwireStore();

  @override
  late final FlutwireSharing sharing = FlutwireSharing(
    native: FlutwireNative(channel: const MethodChannel('flutwire.test/none')),
    store: store,
    temporaryPath: null,
    version: 'test',
  );

  final ValueNotifier<bool> _paused = ValueNotifier(false);
  final ValueNotifier<ThemeMode> _themeMode;
  final ValueNotifier<FlutwireNotificationPermission> _permission;
  final ValueNotifier<bool> _inspectorOpen = ValueNotifier(false);

  /// How many times the screens asked to open the inspector.
  int inspectorOpened = 0;

  /// How many times the screens asked for the notification permission.
  int permissionRequests = 0;

  /// How many times the screens asked for the system notification settings.
  int settingsOpened = 0;

  @override
  ValueListenable<bool> get paused => _paused;

  @override
  void setPaused(bool paused) => _paused.value = paused;

  @override
  ValueListenable<ThemeMode> get themeMode => _themeMode;

  @override
  void setThemeMode(ThemeMode mode) => _themeMode.value = mode;

  @override
  ValueListenable<FlutwireNotificationPermission> get notificationPermission =>
      _permission;

  @override
  Future<FlutwireNotificationPermission> requestNotificationPermission() async {
    permissionRequests++;
    return _permission.value = FlutwireNotificationPermission.granted;
  }

  @override
  Future<void> openNotificationSettings() async => settingsOpened++;

  @override
  ValueListenable<bool> get inspectorOpen => _inspectorOpen;

  @override
  Future<void> openInspector([BuildContext? context]) async {
    inspectorOpened++;
  }

  @override
  Future<void> clear({bool keepPinned = true}) =>
      store.clear(keepPinned: keepPinned);

  /// Lets the screens' listeners hear the history change now.
  void flush() => store.flush();
}
