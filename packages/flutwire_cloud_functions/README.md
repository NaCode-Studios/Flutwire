# flutwire_cloud_functions

Records the Firebase Cloud Functions an app calls in [Flutwire](https://pub.dev/packages/flutwire), the network inspector that opens from the notification shade.

A callable function goes through the native Firebase SDK, which never touches `dart:io`, so the capture that records every other call cannot see it. This package sits on the Dart interface of the `cloud_functions` plugin and records each callable, by name or by URL, with its payload, its result or error code, and how long it took.

## Usage

```bash
flutter pub add flutwire_cloud_functions
```

```dart
await Firebase.initializeApp();
await Flutwire.init();
FlutwireCloudFunctions.install();
```

Nothing else changes. `FirebaseFunctions.instance.httpsCallable('name')` and `httpsCallableFromUrl` keep working as before. Install it before the first call is made, because an instance of `FirebaseFunctions` that already exists keeps talking to the plugin directly. When Flutwire is not recording, such as in a release build, `install` does nothing.

The URL listed for a function is built from the Firebase project id, the region and the function name. Pass `projectId` to `install` when the app cannot say which project it talks to.

## What it does not record

Firestore, Auth, Storage and the other Firebase services speak their own protocols through the native SDKs and are not recorded.
