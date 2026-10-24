import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'capture/wire/send_again.dart';
import 'capture/wire/wire.dart';
import 'config.dart';
import 'coverage.dart';
import 'dock.dart';
import 'engine.dart';
import 'isolate_bridge.dart';
import 'l10n/lookup.dart';
import 'notify/notifier.dart';
import 'platform/native.dart';
import 'resend.dart';
import 'session.dart';
import 'share.dart';
import 'store/open_store.dart';
import 'store/store.dart';
import 'ui/inspector_launcher.dart';
import 'version.dart';

/// Flutwire running in an app: the engine that records, the store that keeps,
/// the notification, and the way the inspector is opened.
///
/// `Flutwire` holds at most one of these. It is the real [FlutwireSession], so
/// the screens work against that interface and never against this class.
final class FlutwireRuntime implements FlutwireSession {
  FlutwireRuntime._({
    required this.engine,
    required FlutwireNative native,
    required FlutwireNotifier notifier,
    required InspectorLauncher launcher,
    required this.dock,
    required this.sharing,
    required ThemeMode themeMode,
    required void Function()? uninstallWire,
  }) : _native = native,
       _notifier = notifier,
       _launcher = launcher,
       themeMode = ValueNotifier(themeMode),
       _uninstallWire = uninstallWire {
    this.themeMode.addListener(_rememberThemeMode);
  }

  static const String _themeKey = 'themeMode';

  /// Starts Flutwire for [config], or returns null when it is not to record in
  /// this build, which is every release build unless the configuration says
  /// otherwise.
  ///
  /// The inspector opens on the navigator of [navigatorKey] when the app gave
  /// it one.
  static Future<FlutwireRuntime?> start(
    FlutwireConfig config, {
    required GlobalKey<NavigatorState> navigatorKey,
  }) async {
    if (!config.isActive) return null;
    WidgetsFlutterBinding.ensureInitialized();
    Locale? locale() => config.locale ?? _deviceLocale();
    final strings = stringsFor(locale());
    final native = FlutwireNative();
    final info = await native.initialize(
      channelName: strings.channelName,
      channelDescription: strings.channelDescription,
      clearLabel: strings.clear,
      shortcutLabel: config.shortcut ? strings.shortcutLabel : null,
    );
    final store = await openStore(
      config,
      defaultPath: () async => info?.storagePath,
    );
    final engine = FlutwireEngine(config: config, store: store);
    final launcher = InspectorLauncher(navigatorKey);
    final dock = FlutwireDock(store.preferences);
    final notifier = FlutwireNotifier(
      native: native,
      store: store,
      config: config.notification,
      inspectorOpen: launcher.isOpen,
      locale: locale,
    );
    final runtime = FlutwireRuntime._(
      engine: engine,
      native: native,
      notifier: notifier,
      launcher: launcher,
      dock: dock,
      sharing: FlutwireSharing(
        native: native,
        store: store,
        temporaryPath: info?.temporaryPath,
        version: flutwireVersion,
      ),
      themeMode:
          ThemeMode.values.asNameMap()[store.preferences.read(_themeKey)] ??
          config.themeMode,
      uninstallWire: config.captureDartIo ? installWireCapture(engine) : null,
    );
    if (config.notification.enabled) {
      // Without a native half there is no shade to post to, and saying so is
      // what lets the floating button take the notification's place.
      notifier.start(
        known: info?.permission ?? FlutwireNotificationPermission.unsupported,
      );
    }
    launcher.isOpen.addListener(runtime._syncInspectorOpen);
    dock.addListener(runtime._syncInspectorOpen);
    runtime._actions = native.actions.listen(runtime._onAction);
    runtime._isolates = FlutwireIsolateBridge.listen(engine);
    switch (await native.consumeInitialAction()) {
      case 'open':
        launcher.openWhenReady(runtime);
      case 'clear':
        unawaited(store.clear());
    }
    return runtime;
  }

  /// The part that records calls.
  final FlutwireEngine engine;

  final FlutwireNative _native;
  final FlutwireNotifier _notifier;
  final InspectorLauncher _launcher;
  final void Function()? _uninstallWire;
  StreamSubscription<String>? _actions;
  FlutwireIsolateBridge? _isolates;
  bool _disposed = false;

  static Locale _deviceLocale() =>
      WidgetsBinding.instance.platformDispatcher.locale;

  @override
  FlutwireConfig get config => engine.config;

  @override
  FlutwireStore get store => engine.store;

  @override
  final FlutwireSharing sharing;

  @override
  ValueNotifier<bool> get paused => engine.paused;

  @override
  final ValueNotifier<ThemeMode> themeMode;

  void _rememberThemeMode() =>
      unawaited(store.preferences.write(_themeKey, themeMode.value.name));

  @override
  ValueListenable<FlutwireNotificationPermission> get notificationPermission =>
      _notifier.permission;

  @override
  Future<FlutwireNotificationPermission> requestNotificationPermission() =>
      _notifier.requestPermission();

  @override
  Future<void> openNotificationSettings() => _notifier.openSettings();

  @override
  ValueListenable<List<FlutwireCoverageNote>> get coverage =>
      engine.coverage.notes;

  @override
  bool get canResend => canSendAgain;

  @override
  Future<int?> resend(FlutwireResend request) => sendAgain(engine, request);

  @override
  final FlutwireDock dock;

  final ValueNotifier<bool> _inspectorOpen = ValueNotifier(false);

  @override
  ValueListenable<bool> get inspectorOpen => _inspectorOpen;

  void _syncInspectorOpen() =>
      _inspectorOpen.value = _launcher.isOpen.value || dock.isOpen;

  @override
  Future<void> openInspector([BuildContext? context]) {
    // Looking is cheap, and the person opening the inspector is about to read
    // what it says about what it missed.
    engine.verifyCapture();
    return _launcher.open(this, context);
  }

  @override
  Future<void> clear({bool keepPinned = true}) =>
      store.clear(keepPinned: keepPinned);

  void _onAction(String action) {
    switch (action) {
      case 'open':
        unawaited(openInspector());
      case 'clear':
        unawaited(clear());
    }
  }

  /// Stops recording and releases everything. Calling it again does nothing.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _launcher.isOpen.removeListener(_syncInspectorOpen);
    dock.removeListener(_syncInspectorOpen);
    _uninstallWire?.call();
    _isolates?.close();
    await _actions?.cancel();
    await _notifier.dispose();
    await _native.dispose();
    await engine.dispose();
    _launcher.dispose();
    dock.dispose();
    _inspectorOpen.dispose();
    themeMode.dispose();
  }
}
