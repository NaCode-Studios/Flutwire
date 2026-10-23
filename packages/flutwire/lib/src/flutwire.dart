import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'capture/recorder.dart';
import 'capture/wire/wire.dart';
import 'config.dart';
import 'engine.dart';
import 'l10n/strings.dart';
import 'model/call.dart';
import 'model/headers.dart';
import 'notify/notifier.dart';
import 'platform/native.dart';
import 'share.dart';
import 'store/open_store.dart';
import 'store/store.dart';
import 'ui/inspector_route.dart';
import 'ui/overlay/floating_button.dart';
import 'version.dart';

/// The sharing service of the running app, for the inspector. Not part of the
/// public API: the library exports only [Flutwire].
FlutwireSharing? get flutwireSharing => Flutwire._sharing;

/// The notifier of the running app, for the inspector's settings.
FlutwireNotifier? get flutwireNotifier => Flutwire._notifier;

/// The engine of the running app, for the inspector's settings.
FlutwireEngine? get flutwireEngine => Flutwire._engine;

/// The entry point of Flutwire.
///
/// ```dart
/// Future<void> main() async {
///   await Flutwire.init();
///   runApp(const MyApp());
/// }
/// ```
///
/// From then on every call made through `dart:io` is recorded, a notification
/// lists the latest ones, and tapping it opens the inspector. In a release
/// build `init` does nothing, and every other member is a harmless no-op.
abstract final class Flutwire {
  static FlutwireEngine? _engine;
  static FlutwireNative? _native;
  static FlutwireNotifier? _notifier;
  static FlutwireSharing? _sharing;
  static StreamSubscription<String>? _actions;
  static void Function()? _uninstallWire;
  static Future<void>? _starting;
  static Timer? _opening;

  static const String _themeKey = 'themeMode';

  static final ValueNotifier<bool> _inspectorOpen = ValueNotifier(false);
  static final ValueNotifier<ThemeMode> _themeMode = ValueNotifier(
    ThemeMode.system,
  );
  static final ValueNotifier<List<FlutwireCall>> _none = ValueNotifier(
    const [],
  );

  /// Give this to the app's navigator so the inspector opens above the app's
  /// own routes. It is optional: without it Flutwire finds the root navigator
  /// itself.
  ///
  /// ```dart
  /// MaterialApp(navigatorKey: Flutwire.navigatorKey, ...)
  /// ```
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>(debugLabel: 'Flutwire');

  /// Starts recording. Call it once, as early as possible in `main`: only the
  /// clients created after it are seen. Calling it again does nothing.
  static Future<void> init({FlutwireConfig config = const FlutwireConfig()}) =>
      _starting ??= _start(config);

  static Future<void> _start(FlutwireConfig config) async {
    if (!config.isActive) return;
    WidgetsFlutterBinding.ensureInitialized();
    final strings = FlutwireStrings.of(config.locale ?? _deviceLocale());
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
    _engine = engine;
    _native = native;
    _themeMode.value =
        ThemeMode.values.asNameMap()[store.preferences.read(_themeKey)] ??
        config.themeMode;
    if (config.captureDartIo) _uninstallWire = installWireCapture(engine);

    final notifier = FlutwireNotifier(
      native: native,
      store: store,
      config: config.notification,
      inspectorOpen: _inspectorOpen,
      locale: () => config.locale ?? _deviceLocale(),
    );
    _notifier = notifier;
    _sharing = FlutwireSharing(
      native: native,
      store: store,
      temporaryPath: info?.temporaryPath,
      version: flutwireVersion,
    );
    if (config.notification.enabled && info != null) {
      notifier.start(known: info.permission);
    }

    _actions = native.actions.listen(_onAction);
    switch (await native.consumeInitialAction()) {
      case 'open':
        _openWhenReady();
      case 'clear':
        unawaited(store.clear());
    }
  }

  static Locale _deviceLocale() =>
      WidgetsBinding.instance.platformDispatcher.locale;

  static void _onAction(String action) {
    switch (action) {
      case 'open':
        unawaited(open());
      case 'clear':
        unawaited(clear());
    }
  }

  /// Whether Flutwire is recording in this build.
  static bool get isActive => _engine != null;

  /// The configuration in force, or the defaults before [init] has run.
  static FlutwireConfig get config => _engine?.config ?? const FlutwireConfig();

  /// The recorded calls, newest first. Empty while Flutwire is not recording.
  static ValueListenable<List<FlutwireCall>> get calls =>
      _engine?.store.calls ?? _none;

  /// The store behind [calls], for reading the full call with its bodies.
  static FlutwireStore? get store => _engine?.store;

  /// Whether recording is paused.
  static bool get isPaused => _engine?.isPaused ?? false;

  static set isPaused(bool value) => _engine?.isPaused = value;

  /// Notifies when recording is paused or resumed.
  static ValueListenable<bool> get pausedListenable =>
      _engine?.pausedListenable ?? ValueNotifier(false);

  /// The look of the inspector: dark, light, or whichever the device uses.
  ///
  /// It starts as [FlutwireConfig.themeMode], and from the moment someone picks
  /// a look in the settings that pick wins and is remembered next to the
  /// history.
  static ThemeMode get themeMode => _themeMode.value;

  static set themeMode(ThemeMode mode) {
    _themeMode.value = mode;
    unawaited(_engine?.store.preferences.write(_themeKey, mode.name));
  }

  /// Notifies when the look of the inspector changes.
  static ValueListenable<ThemeMode> get themeModeListenable => _themeMode;

  /// Whether the `dart:io` capture is installed. Client adapters check it to
  /// avoid recording a call twice.
  static bool get wireCaptureActive => _engine?.wireCaptureActive ?? false;

  /// Whether the user has allowed the notification, as far as is known.
  static ValueListenable<FlutwireNotificationPermission>
  get notificationPermission =>
      _notifier?.permission ??
      ValueNotifier(FlutwireNotificationPermission.unsupported);

  /// Whether the inspector is on screen.
  static ValueListenable<bool> get inspectorOpen => _inspectorOpen;

  /// For `MaterialApp.builder` and `WidgetsApp.builder`: floats a small button
  /// above the app that opens the inspector, and listens for Ctrl or Cmd with
  /// Shift and L. It is meant for the web, Windows and Linux, where there is no
  /// notification to open the inspector from, and it shows only there unless
  /// [FlutwireConfig.floatingButton] says otherwise.
  ///
  /// ```dart
  /// MaterialApp(builder: Flutwire.builder, ...)
  /// ```
  static Widget builder(BuildContext context, Widget? child) =>
      FlutwireOverlay(child: child ?? const SizedBox.shrink());

  /// Starts recording one call. This is what a capture adapter calls; an app
  /// that only uses `dart:io` never needs it. Returns null when the call
  /// should not be recorded.
  static FlutwireCallRecorder? begin({
    required String method,
    required Uri uri,
    required FlutwireSource source,
    FlutwireHeaders requestHeaders = FlutwireHeaders.empty,
  }) => _engine?.begin(
    method: method,
    uri: uri,
    source: source,
    requestHeaders: requestHeaders,
  );

  /// Removes every recorded call, except the pinned ones when [keepPinned] is
  /// true.
  static Future<void> clear({bool keepPinned = true}) async {
    await _engine?.store.clear(keepPinned: keepPinned);
  }

  /// Asks the user for the notification permission, from a button.
  static Future<FlutwireNotificationPermission>
  requestNotificationPermission() async =>
      await _notifier?.requestPermission() ??
      FlutwireNotificationPermission.unsupported;

  /// Opens the system page where notifications can be allowed.
  static Future<void> openNotificationSettings() async =>
      _notifier?.openSettings();

  /// Opens the inspector above the app. [context] is optional: without one
  /// the navigator from [navigatorKey], or else the root navigator, is used.
  ///
  /// Does nothing if the inspector is already open or Flutwire is not
  /// recording.
  static Future<void> open([BuildContext? context]) async {
    final engine = _engine;
    if (engine == null || _inspectorOpen.value) return;
    final navigator = context != null
        ? Navigator.maybeOf(context, rootNavigator: true)
        : (navigatorKey.currentState ?? _findNavigator());
    if (navigator == null) return;
    _inspectorOpen.value = true;
    try {
      await navigator.push(inspectorRoute());
    } finally {
      _inspectorOpen.value = false;
    }
  }

  /// A cold start from the notification: the app has no navigator yet, so keep
  /// looking for one until the first screen is up.
  static void _openWhenReady() {
    _opening?.cancel();
    var attempts = 0;
    _opening = Timer.periodic(const Duration(milliseconds: 150), (timer) {
      attempts++;
      if (navigatorKey.currentState != null || _findNavigator() != null) {
        timer.cancel();
        unawaited(open());
      } else if (attempts > 100) {
        timer.cancel();
      }
    });
  }

  /// The outermost navigator in the widget tree, found without the app handing
  /// it over.
  static NavigatorState? _findNavigator() {
    final root = WidgetsBinding.instance.rootElement;
    if (root == null) return null;
    NavigatorState? found;
    void visit(Element element) {
      if (found != null) return;
      if (element is StatefulElement && element.state is NavigatorState) {
        found = element.state as NavigatorState;
        return;
      }
      element.visitChildren(visit);
    }

    visit(root);
    return found;
  }

  /// Stops recording and releases everything. Meant for tests.
  @visibleForTesting
  static Future<void> reset() async {
    _opening?.cancel();
    _uninstallWire?.call();
    await _actions?.cancel();
    await _notifier?.dispose();
    await _native?.dispose();
    await _engine?.dispose();
    _engine = null;
    _native = null;
    _notifier = null;
    _sharing = null;
    _actions = null;
    _uninstallWire = null;
    _starting = null;
    _inspectorOpen.value = false;
    _themeMode.value = ThemeMode.system;
  }
}
