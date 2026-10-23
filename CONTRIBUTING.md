# Contributing

Flutwire is pre-alpha and the architecture is still moving. If you are thinking about a substantial change, open an issue first so we can agree on the shape before anyone writes code.

## Layout

| Path | What lives there |
| --- | --- |
| `packages/flutwire` | The package: call model, capture, storage, export, notifications and the inspector UI, with its Android and Apple halves |
| `packages/flutwire/example` | A Flutter app that makes every kind of call, for trying the package by hand |
| `packages/flutwire_dio` | The Dio interceptor, for the web and for adapters that do not use `dart:io` |
| `packages/flutwire_http` | The `package:http` client, for the same places |
| `packages/flutwire_cloud_functions` | Firebase callable functions, which go through the native SDK and never reach `dart:io` |
| `docs/brand` | The brand kit |

## How the code fits together

`Flutwire` is a thin facade. `Flutwire.init` builds a `FlutwireRuntime`, which wires the engine that records, the store that keeps, the notifier and the native bridge, and which is the one implementation of `FlutwireSession`. The inspector never reads `Flutwire` or the runtime: its screens work on the session they find in `FlutwireScope`, which is why they are tested against a fake. A capture adapter asks `Flutwire.begin` for a recorder and reports into it. The public API is what `lib/flutwire.dart` exports, and everything under `lib/src` is internal.

## Ground rules

Recording never changes the traffic. The capture layer observes bytes and hands them on untouched, in the same order and at the same pace. A failure inside Flutwire is caught and counted, and is never thrown into the request the app made.

Nothing is recorded in a release build unless the app asks for it. The history can hold tokens and personal data, so `Flutwire.init` does nothing under `kReleaseMode` unless `allowInRelease` is set.

Policy lives in Dart and the native halves only relay. Notification text, ordering and throttling are decided in Dart and passed down as plain values, so Android, iOS and macOS cannot drift apart.

Secrets are masked when a call is recorded, not when it is shown. Redaction runs before a call reaches memory, disk, a notification or an export.

## Local setup

```bash
flutter pub get
```

```bash
dart format --output=none --set-exit-if-changed packages
flutter analyze --fatal-infos
(cd packages/flutwire && flutter test)
(cd packages/flutwire_dio && flutter test)
(cd packages/flutwire_http && flutter test)
(cd packages/flutwire_cloud_functions && flutter test)
```

The Android and Apple halves are compiled by building the example app: `flutter build apk --debug`, `flutter build ios --simulator --no-codesign` and `flutter build macos --debug`, each from `packages/flutwire/example`.

## Commits and branches

`main` is protected; work on a branch and open a pull request. Keep commits scoped to one change and write the message in the imperative mood.
