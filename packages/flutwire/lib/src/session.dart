import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/widgets.dart';

import 'config.dart';
import 'platform/native.dart' show FlutwireNotificationPermission;
import 'share.dart';
import 'store/store.dart';

/// What the inspector needs from a running Flutwire.
///
/// No screen reads a global. The scope at the top of the inspector hands the
/// screens one of these, which is what lets a test give them a fake and see
/// them work with no platform behind them.
abstract interface class FlutwireSession {
  /// The configuration in force.
  FlutwireConfig get config;

  /// The history, with the bodies of a call read back on demand.
  FlutwireStore get store;

  /// Writes calls out of the app.
  FlutwireSharing get sharing;

  /// Whether recording is paused. Setting it pauses or resumes.
  ValueNotifier<bool> get paused;

  /// The look of the inspector. Setting it picks another, which is remembered.
  ValueNotifier<ThemeMode> get themeMode;

  /// Whether the user has allowed the notification, as far as is known.
  ValueListenable<FlutwireNotificationPermission> get notificationPermission;

  /// Asks the user for the notification permission, from a button.
  Future<FlutwireNotificationPermission> requestNotificationPermission();

  /// Opens the system page where notifications can be allowed.
  Future<void> openNotificationSettings();

  /// Whether the inspector is on screen.
  ValueListenable<bool> get inspectorOpen;

  /// Opens the inspector above the app. Without a [context] the app's
  /// navigator is found by other means. Does nothing if the inspector is
  /// already open.
  Future<void> openInspector([BuildContext? context]);

  /// Removes every recorded call, except the pinned ones when [keepPinned] is
  /// true.
  Future<void> clear({bool keepPinned = true});
}
