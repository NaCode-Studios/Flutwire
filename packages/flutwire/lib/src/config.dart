import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;

import 'capture/redaction.dart';
import 'model/body.dart';
import 'model/call.dart';

/// When a floating button, which opens the inspector, shows above the app.
enum FlutwireButtonMode {
  /// Only where there is no notification to open it from: the web, Windows and
  /// Linux, or when the notification is turned off in the configuration.
  auto,

  /// Always.
  always,

  /// Never.
  never,
}

/// How long recorded calls are kept.
enum FlutwireRetention {
  /// One hour.
  oneHour(Duration(hours: 1)),

  /// One day.
  oneDay(Duration(days: 1)),

  /// One week.
  oneWeek(Duration(days: 7)),

  /// Until the user clears them or a limit pushes them out.
  forever(null);

  const FlutwireRetention(this.period);

  /// How long a call is kept, or null for no time limit.
  final Duration? period;
}

/// A rule that keeps matching calls out of the history.
///
/// Ignored calls are not recorded at all: no body is buffered and nothing
/// reaches the notification. Use it for chatty analytics endpoints and for
/// traffic that carries nothing worth inspecting.
@immutable
final class FlutwireIgnore {
  const FlutwireIgnore._(this._matches);

  /// Ignores calls to [host], and to its subdomains when [subdomains] is true.
  factory FlutwireIgnore.host(String host, {bool subdomains = false}) {
    final wanted = host.toLowerCase();
    return FlutwireIgnore._((method, uri) {
      final actual = uri.host.toLowerCase();
      return actual == wanted || (subdomains && actual.endsWith('.$wanted'));
    });
  }

  /// Ignores calls whose path starts with [prefix].
  factory FlutwireIgnore.pathPrefix(String prefix) =>
      FlutwireIgnore._((method, uri) => uri.path.startsWith(prefix));

  /// Ignores calls whose full URL matches [pattern].
  factory FlutwireIgnore.url(RegExp pattern) =>
      FlutwireIgnore._((method, uri) => pattern.hasMatch(uri.toString()));

  /// Ignores calls for which [test] returns true.
  factory FlutwireIgnore.where(bool Function(String method, Uri uri) test) =>
      FlutwireIgnore._(test);

  final bool Function(String method, Uri uri) _matches;

  /// Whether a call to [uri] with [method] is ignored.
  bool matches(String method, Uri uri) => _matches(method, uri);
}

/// Turns a body into text the inspector can show, for formats it does not
/// know, such as Protobuf or MessagePack.
///
/// Decoders run when a body is displayed, not when it is recorded, so a slow
/// one never delays the app's own request and a persisted call can still be
/// decoded after a restart.
abstract interface class FlutwireBodyDecoder {
  /// A short name for the format, shown next to the decoded text.
  String get name;

  /// A readable rendering of [body], or null if this decoder does not
  /// recognise it. The first decoder that answers wins.
  String? decode(
    FlutwireCall call,
    FlutwireBody body, {
    required bool isRequest,
  });
}

/// How the notification in the shade behaves.
@immutable
final class FlutwireNotificationConfig {
  /// Creates a notification policy.
  const FlutwireNotificationConfig({
    this.enabled = true,
    this.requestPermission = true,
    this.lines = 10,
    this.throttle = const Duration(milliseconds: 600),
    this.hideWhileInspectorOpen = true,
  });

  /// Whether to post the notification at all.
  final bool enabled;

  /// Whether to ask for the notification permission on the first call, where
  /// the platform requires one.
  final bool requestPermission;

  /// How many recent calls the notification lists.
  final int lines;

  /// The shortest time between two updates of the notification. Calls that
  /// arrive in between are folded into the next update.
  final Duration throttle;

  /// Whether to withdraw the notification while the inspector is on screen.
  final bool hideWhileInspectorOpen;
}

/// Everything Flutwire can be told about the app it runs in.
///
/// The defaults are meant to work with no configuration: debug builds only,
/// history kept for a week, credentials hidden.
@immutable
final class FlutwireConfig {
  /// Creates a configuration.
  const FlutwireConfig({
    this.enabled,
    this.allowInRelease = false,
    this.captureDartIo = true,
    this.maxBodyBytes = 250000,
    this.maxCalls = 500,
    this.maxMemoryBytes = 32 * 1024 * 1024,
    this.maxDiskBytes = 128 * 1024 * 1024,
    this.retention = FlutwireRetention.oneWeek,
    this.persist = true,
    this.storagePath,
    this.redaction = const FlutwireRedaction(),
    this.ignore = const [],
    this.decoders = const [],
    this.notification = const FlutwireNotificationConfig(),
    this.shortcut = true,
    this.locale,
    this.themeMode = ThemeMode.system,
    this.floatingButton = FlutwireButtonMode.auto,
  });

  /// Whether recording is on. Null means on in debug builds and off in
  /// profile and release builds.
  final bool? enabled;

  /// Whether a release build may record. Release builds ignore [enabled]
  /// unless this is set, because the history can hold tokens and personal data.
  final bool allowInRelease;

  /// Whether to install the `dart:io` capture, which records the calls of every
  /// client built on `HttpClient` without any per-client setup. It has no
  /// effect on the web.
  final bool captureDartIo;

  /// How many bytes of a body are kept, per request and per response. The
  /// real size is always recorded.
  final int maxBodyBytes;

  /// How many calls the history keeps.
  final int maxCalls;

  /// How many bytes of bodies are held in memory before the oldest are
  /// released (to disk when [persist] is on, otherwise for good).
  final int maxMemoryBytes;

  /// How many bytes of bodies are kept on disk.
  final int maxDiskBytes;

  /// How long calls are kept.
  final FlutwireRetention retention;

  /// Whether to keep the history on disk, so it survives a restart and a
  /// notification can open it after the app was killed.
  final bool persist;

  /// The folder to keep the history in. Defaults to a folder under the
  /// application support directory. It is a path rather than a `Directory` so
  /// that the package stays importable on the web, where there is no disk.
  final String? storagePath;

  /// What to hide from recorded calls.
  final FlutwireRedaction redaction;

  /// Calls to leave out of the history.
  final List<FlutwireIgnore> ignore;

  /// Decoders for formats the inspector does not read on its own.
  final List<FlutwireBodyDecoder> decoders;

  /// The notification in the shade.
  final FlutwireNotificationConfig notification;

  /// Whether to add an "Open Flutwire" shortcut to the app icon.
  final bool shortcut;

  /// The language of the notification and the inspector. Null follows the
  /// device.
  final Locale? locale;

  /// When a floating button shows above the app. It needs the app to hand
  /// `Flutwire.builder` to its `MaterialApp` or `WidgetsApp`.
  final FlutwireButtonMode floatingButton;

  /// The look the inspector starts with: dark, light, or the device's. Whoever
  /// opens the inspector's settings can pick another, and that pick is
  /// remembered and wins over this.
  final ThemeMode themeMode;

  /// Whether this configuration records in the current build mode.
  bool get isActive {
    if (kReleaseMode) return allowInRelease && (enabled ?? true);
    return enabled ?? kDebugMode;
  }
}
