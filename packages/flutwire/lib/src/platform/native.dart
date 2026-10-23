import 'dart:async';

import 'package:flutter/services.dart';

/// Whether the app may post notifications.
enum FlutwireNotificationPermission {
  /// Notifications are allowed.
  granted,

  /// The user refused them, or turned them off in the system settings.
  denied,

  /// The user has not been asked yet.
  notDetermined,

  /// This platform has no notification shade Flutwire can use.
  unsupported;

  /// Reads the string the native side sends.
  static FlutwireNotificationPermission parse(Object? raw) => switch (raw) {
    'granted' => granted,
    'denied' => denied,
    'notDetermined' => notDetermined,
    _ => unsupported,
  };
}

/// What the native half reports when it starts.
final class FlutwireNativeInfo {
  /// Creates a report.
  const FlutwireNativeInfo({
    required this.permission,
    this.storagePath,
    this.temporaryPath,
  });

  /// Whether notifications are allowed.
  final FlutwireNotificationPermission permission;

  /// A private folder for the history, excluded from backups.
  final String? storagePath;

  /// A folder for files about to be shared.
  final String? temporaryPath;
}

/// The Dart side of the native half: Android, iOS and macOS code that posts the
/// notification, shares files and reports what the user did with them.
///
/// Policy stays in Dart. Everything here takes plain values, so the three
/// platforms cannot drift apart, and every call is safe on a platform without
/// the native half: it answers with a neutral value instead of throwing.
class FlutwireNative {
  /// Creates a bridge over [channel], or over the real channel by default.
  FlutwireNative({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName) {
    _channel.setMethodCallHandler(_onCall);
  }

  static const String _channelName = 'it.nacodestudios.flutwire/native';

  final MethodChannel _channel;
  final StreamController<String> _actions = StreamController.broadcast();
  bool _missing = false;

  /// What the user did in the notification or the shortcut: `open` or `clear`.
  Stream<String> get actions => _actions.stream;

  /// Whether the native half is absent on this platform.
  bool get isMissing => _missing;

  Future<Object?> _onCall(MethodCall call) async {
    if (call.method == 'onAction' && call.arguments is String) {
      _actions.add(call.arguments as String);
    }
    return null;
  }

  Future<T?> _invoke<T>(String method, [Object? arguments]) async {
    if (_missing) return null;
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      _missing = true;
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Starts the native half. Returns null when there is none.
  Future<FlutwireNativeInfo?> initialize({
    required String channelName,
    required String channelDescription,
    required String clearLabel,
    String? shortcutLabel,
  }) async {
    final reply = await _invoke<Map<Object?, Object?>>('initialize', {
      'channelName': channelName,
      'channelDescription': channelDescription,
      'clearLabel': clearLabel,
      'shortcutLabel': shortcutLabel,
    });
    if (reply == null) return null;
    return FlutwireNativeInfo(
      permission: FlutwireNotificationPermission.parse(reply['permission']),
      storagePath: reply['storagePath'] as String?,
      temporaryPath: reply['temporaryPath'] as String?,
    );
  }

  /// The action that launched the app, or that arrived while it was not
  /// running. Reading it clears it.
  Future<String?> consumeInitialAction() => _invoke<String>('consumeAction');

  /// The current permission.
  Future<FlutwireNotificationPermission> permission() async =>
      FlutwireNotificationPermission.parse(await _invoke<String>('permission'));

  /// Asks the user for permission where the platform requires it, and
  /// returns the answer.
  Future<FlutwireNotificationPermission> requestPermission() async =>
      FlutwireNotificationPermission.parse(
        await _invoke<String>('requestPermission'),
      );

  /// Posts the notification, or updates it in place.
  Future<void> showSummary({
    required String title,
    required List<String> lines,
    required String summary,
    required int count,
    required String clearLabel,
  }) => _invoke<void>('showSummary', {
    'title': title,
    'lines': lines,
    'summary': summary,
    'count': count,
    'clearLabel': clearLabel,
  });

  /// Withdraws the notification.
  Future<void> cancelSummary() => _invoke<void>('cancelSummary');

  /// Opens the system page where the user can allow notifications.
  Future<void> openNotificationSettings() =>
      _invoke<void>('openNotificationSettings');

  /// Opens the system share sheet. [origin] anchors the sheet on an iPad or a
  /// Mac. Returns whether a sheet was shown.
  Future<bool> share({
    String? text,
    String? filePath,
    String? mimeType,
    String? subject,
    Rect? origin,
  }) async =>
      await _invoke<bool>('share', {
        'text': text,
        'filePath': filePath,
        'mimeType': mimeType,
        'subject': subject,
        if (origin != null)
          'origin': [origin.left, origin.top, origin.width, origin.height],
      }) ??
      false;

  /// Releases the listeners.
  Future<void> dispose() async {
    _channel.setMethodCallHandler(null);
    await _actions.close();
  }
}
