import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/widgets.dart';

import 'config.dart';
import 'coverage.dart';
import 'dock.dart';
import 'intercept/interception.dart';
import 'platform/native.dart' show FlutwireNotificationPermission;
import 'resend.dart';
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

  /// What Flutwire has noticed about its own blind spots, empty while nothing
  /// is wrong.
  ValueListenable<List<FlutwireCoverageNote>> get coverage;

  /// Whether a call can be sent again from the inspector. It cannot on the web,
  /// where there is no `dart:io` to send it with.
  bool get canResend;

  /// Sends [request] and records it as a call that repeats the one it names.
  /// Returns the id of the recorded call as soon as the request is on its way,
  /// or null when it could not be recorded. The call fills in as the answer
  /// arrives.
  Future<int?> resend(FlutwireResend request);

  /// The rules that answer a request or hold it, and the requests held. Null
  /// where the app did not turn interception on, or cannot have it, as on the
  /// web.
  FlutwireInterception? get interception;

  /// The panel the inspector can sit in beside the app.
  FlutwireDock get dock;

  /// Whether the inspector is on screen, full screen or docked.
  ValueListenable<bool> get inspectorOpen;

  /// Opens the inspector above the app. Without a [context] the app's
  /// navigator is found by other means. Does nothing if the inspector is
  /// already open.
  Future<void> openInspector([BuildContext? context]);

  /// Removes every recorded call, except the pinned ones when [keepPinned] is
  /// true.
  Future<void> clear({bool keepPinned = true});
}
