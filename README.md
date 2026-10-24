<p align="center">
  <img src="docs/flutwire-hero.png" alt="Flutwire, a network inspector for Flutter" width="100%">
</p>

# Flutwire

**A network inspector for Flutter that opens from the notification shade.**

[![CI](https://img.shields.io/github/actions/workflow/status/NaCode-Studios/Flutwire/ci.yaml?branch=main&label=CI&labelColor=141518&style=flat-square)](https://github.com/NaCode-Studios/Flutwire/actions/workflows/ci.yaml)
[![pub.dev](https://img.shields.io/pub/v/flutwire?label=pub.dev&labelColor=141518&color=F0803A&style=flat-square)](https://pub.dev/packages/flutwire)
[![pub points](https://img.shields.io/pub/points/flutwire?labelColor=141518&color=F0803A&style=flat-square)](https://pub.dev/packages/flutwire/score)
[![License](https://img.shields.io/badge/license-Apache--2.0-F0803A?labelColor=141518&style=flat-square)](LICENSE)

When an app misbehaves on a phone, the call that explains it is usually out of reach. The console shows only what a logger was told to print. A proxy needs a certificate on the device and a changed Wi-Fi setting. Every HTTP client in the app has to be wired by hand before it says anything, and when the app is killed the evidence goes with it.

Flutwire records the calls an app makes, keeps them on the device and lists the latest ones in the notification shade. Tapping it opens the inspector, and each call opens in full: URL, timings, headers, cookies, and the request and response bodies as a JSON tree, indented text, form fields, an image or a hex dump. A debug build needs one line in `main`; a release build records nothing.

```bash
flutter pub add flutwire
```

```dart
Future<void> main() async {
  await Flutwire.init();
  runApp(const MyApp());
}
```

From then on every call that goes through `dart:io` is recorded: `package:http`, Dio's default adapter, Chopper, `Image.network`, anything that ends in an `HttpClient`. Three small packages cover what `dart:io` does not reach.

```dart
dio.interceptors.add(FlutwireDioInterceptor());   // flutwire_dio, for the web
final client = FlutwireClient(http.Client());     // flutwire_http, for the web
FlutwireCloudFunctions.install();                 // flutwire_cloud_functions, after Firebase.initializeApp
MaterialApp(builder: Flutwire.builder);           // a button where there is no notification
```

This is what the notification lists, and what a call becomes when it is shared as a command:

```text
201 POST api.example.com/v1/orders · 148 ms
404 GET api.example.com/v1/clubs/9 · 96 ms
ERR GET api.example.com/health
```

```bash
curl -X POST 'https://api.example.com/v1/orders' \
  -H 'content-type: application/json' \
  -H 'authorization: [redacted]' \
  --data-raw '{"items":[{"sku":"A-12","qty":2}]}'
```

Flutwire reads traffic and never changes it. It does not proxy other apps, and it cannot see what never passes through Dart: Firestore, Auth and Storage speak their own protocols through native SDKs. When a call may have gone unseen, because a client does not use `dart:io`, because an adapter ran in another isolate or because something replaced the capture, the inspector says so above the list and says what to change. Authorization and cookie values are masked when a call is recorded, so they never reach memory, disk, a notification or an export.

In a release build `Flutwire.init` does nothing: no call is recorded, no file is written and no notification is posted. The plugin's native code still ships in the app, like any other plugin's, and on Android its manifest adds the notification permission to the merged one.

> **Status — `0.1`, alpha.** Minor versions may still break the API until `1.0`. The plan is on [the project board](https://github.com/orgs/NaCode-Studios/projects/13).

## Why Flutwire

**It needs no wiring.** One `await Flutwire.init()` records every call that goes through `dart:io`, including the ones made by packages you did not write. There is no interceptor to add to each client and no certificate to install. The test suite makes calls with `http`, Dio and a raw `HttpClient` and checks that each one is recorded with no per-client setup.

**The history outlives the app.** A call is written to disk as soon as it ends, and the notification survives the process. Kill the app, tap the notification and the inspector opens on the calls read back from disk. Retention runs from one hour to forever, a cap on the number of calls and on bytes keeps the folder small, and a pinned call is never removed.

**It searches the payloads, not only the URLs.** The list search looks at URLs, status codes, GraphQL operation names, headers and the text of request and response bodies, so finding where an id came from is one query. Inside a body, search highlights every match and jumps between them.

**It sees what `dart:io` cannot.** Firebase callable functions travel through the native SDK, so no HTTP-level capture sees them. `flutwire_cloud_functions` sits on the Dart side of the `cloud_functions` plugin and records each callable, by name or by URL, with its payload, its result or error code and how long it took. The app's code does not change.

## Architecture

```text
Flutwire
├── packages/flutwire                 the package
│   ├── lib/src/capture               the HttpClient wrapper, the recorder, redaction
│   ├── lib/src/model                 a call, its bodies, headers, cookies, multipart parts
│   ├── lib/src/store                 the history in memory and on disk, and preferences
│   ├── lib/src/export                cURL, HAR 1.2, text and JSON
│   ├── lib/src/notify                what the notification says and when it changes
│   ├── lib/src/ui                    the inspector, the body viewer, settings
│   ├── android, darwin               the native halves
│   └── example                       an app that makes every kind of call
├── packages/flutwire_dio             a Dio interceptor
├── packages/flutwire_http            a package:http client
├── packages/flutwire_cloud_functions Firebase callable functions
└── docs/brand                        the brand kit
```

| Component | What it does |
| --- | --- |
| Capture | Wraps `HttpClient` through `HttpOverrides`, copies the byte streams as they pass and hands the copies to the recorder. The app gets its bytes untouched, in order and at the same pace. |
| Model | A call with its bodies cut at a limit that keeps the real size, GraphQL operation names, and the redaction policy. |
| Store | The history in memory and on disk with retention and limits, and what the user picked in the settings. |
| Export | A call or many as cURL, HAR 1.2, text or JSON, and a body as a file. |
| Notify | Decides what the notification lists and when it updates. The native halves only relay. |
| Inspector | The list, the call in full, the body viewer and the settings, in dark and light, in English and Italian. |
| Adapters | The Dio interceptor, the `http` client and the Cloud Functions recorder, for the places `dart:io` does not reach. |

## Roadmap

**Shipped (`0.1.0`).** Capture, the history on disk, the notification on Android, iOS and macOS, the inspector with the body viewer, export, the adapters and the example app. [`CHANGELOG.md`](CHANGELOG.md) has the detail.

**Next, `0.2.0`: beyond the interceptor.** Editing and resending a call, WebSocket and server-sent event frames, comparing two calls, mocking a response, calls made from other isolates, statistics and a waterfall, and decoders for Protobuf and MessagePack. The ideas that were turned down, with the reason, are on the board too.

The plan lives on [the project board](https://github.com/orgs/NaCode-Studios/projects/13) and is mirrored as [milestones](https://github.com/NaCode-Studios/Flutwire/milestones).

## Building and testing

```bash
flutter pub get
```

```bash
flutter analyze --fatal-infos
```

Each package has its own suite: run `flutter test` inside `packages/flutwire`, `packages/flutwire_dio`, `packages/flutwire_http` and `packages/flutwire_cloud_functions`.

The Android and Apple halves are compiled by building the example app from `packages/flutwire/example`: `flutter build apk --debug`, `flutter build ios --simulator --no-codesign` and `flutter build macos --debug`.

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md) first. For anything larger than a fix, open an issue so the shape is agreed before the code is written.

## License

Apache-2.0, in [LICENSE](LICENSE).

## Sponsor

Flutwire is built by NaCode Studios. If it is useful to you, you can [sponsor the studio](https://github.com/sponsors/NaCode-Studios).
