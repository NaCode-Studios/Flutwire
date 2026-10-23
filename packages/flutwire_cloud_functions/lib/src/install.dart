import 'package:cloud_functions_platform_interface/cloud_functions_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutwire/flutwire.dart';

import 'platform.dart';

/// Records the Firebase callable functions the app calls.
///
/// ```dart
/// await Firebase.initializeApp();
/// await Flutwire.init();
/// FlutwireCloudFunctions.install();
/// ```
///
/// Nothing else changes: `FirebaseFunctions.instance.httpsCallable('name')` and
/// `httpsCallableFromUrl` keep working as before, and each call shows up in the
/// inspector with its name, its payload, its result or its error code, and how
/// long it took. Install it before the first call is made, because an instance
/// of `FirebaseFunctions` that already exists keeps talking to the plugin
/// directly.
///
/// Firestore, Auth, Storage and the other Firebase services speak their own
/// protocols through the native SDKs and are not recorded.
abstract final class FlutwireCloudFunctions {
  static FirebaseFunctionsPlatform? _original;

  /// Whether the recording is installed.
  static bool get isInstalled => _original != null;

  /// Starts recording callable functions. Calling it again does nothing, and so
  /// does calling it when Flutwire is not recording, such as in a release
  /// build.
  ///
  /// The URL shown for a function is built from the Firebase project id, the
  /// region and the function name. Pass [projectId] to write another project
  /// id there when the app cannot say which one it talks to.
  static void install({String? projectId}) {
    if (isInstalled || !Flutwire.isActive) return;
    final original = FirebaseFunctionsPlatform.instance;
    _original = original;
    FirebaseFunctionsPlatform.instance = FlutwireFunctionsPlatform(
      original,
      projectId: projectId,
    );
  }

  /// Puts the plugin back as it was. Meant for tests.
  @visibleForTesting
  static void uninstall() {
    final original = _original;
    if (original == null) return;
    FirebaseFunctionsPlatform.instance = original;
    _original = null;
  }
}
