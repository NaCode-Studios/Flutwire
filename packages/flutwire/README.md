<p align="center">
  <img src="https://raw.githubusercontent.com/NaCode-Studios/Flutwire/main/docs/flutwire-hero.png" alt="Flutwire, a network inspector for Flutter" width="100%">
</p>

# flutwire

**A network inspector for Flutter that opens from the notification shade.**

Flutwire records the HTTP calls an app makes, keeps them on the device and lists the latest ones in the notification shade. Tapping it opens the inspector, and each call opens in full: URL, timings, headers, cookies, and the request and response bodies as a JSON tree, indented text, form fields, an image or a hex dump. A call can be edited and sent again from the same screen, and a WebSocket or an event stream lists its messages as they arrive.

<p align="center">
  <a href="https://github.com/NaCode-Studios/Flutwire/blob/main/docs/media/flutwire-demo.mp4"><img src="https://raw.githubusercontent.com/NaCode-Studios/Flutwire/main/docs/media/flutwire-demo.gif" alt="The notification in the shade lists the latest calls, and tapping it opens the inspector, where a call opens as a JSON tree" width="300"></a><br>
  <sub><a href="https://github.com/NaCode-Studios/Flutwire/blob/main/docs/media/flutwire-demo.mp4">Watch the whole tour</a>, 40 seconds on an Android emulator.</sub>
</p>

## Getting started

```bash
flutter pub add flutwire
```

```dart
Future<void> main() async {
  await Flutwire.init();
  runApp(const MyApp());
}
```

That is the whole integration. From then on every call that goes through `dart:io` is recorded, including the ones made by packages you did not write: `package:http`, Dio's default adapter, Chopper, `Image.network`. In a release build `init` does nothing and nothing is recorded.

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/NaCode-Studios/Flutwire/main/docs/media/flutwire-tour-light.png">
    <img src="https://raw.githubusercontent.com/NaCode-Studios/Flutwire/main/docs/media/flutwire-tour-dark.png" alt="The notification in the shade, the list of calls, a JSON body as a tree and the search across headers and bodies" width="100%">
  </picture>
</p>

## Opening the inspector

On Android, iOS and macOS the notification opens it. On Android 13 and later Flutwire asks for the notification permission the first time there is something to show. If the user declines, `Flutwire.open()` and the "Open Flutwire" shortcut on the app icon still work.

The web, Windows and Linux have no notification. Hand the builder to the app and a small button floats above it, with the Ctrl or Cmd, Shift and L shortcut beside it. The navigator key is optional and makes the inspector open above the app's own routes.

```dart
MaterialApp(
  navigatorKey: Flutwire.navigatorKey,
  builder: Flutwire.builder,
  home: const Home(),
);
```

## WebSockets and event streams

A WebSocket opened through `dart:io` is one call that stays open. Its Messages tab lists every message and control frame in the order it crossed, which way it went, how big it was and when, and a compressed message is shown after it is decompressed. An event stream (`text/event-stream`) lists its events as they complete, with their names and ids, and the raw stream stays the body of the response. Only the latest 1000 messages are kept, and the tab says how many came before them.

`dart:io` makes one client for all WebSockets the first time one is opened, so a WebSocket opened before `Flutwire.init` is not seen: call `init` first thing in `main`. On the web the browser opens WebSockets itself, and none is recorded there.

## Sending a call again

Open a call and tap the replay button in the top bar. The method, the address, the header fields and the body can all be changed, and Send makes the request. What goes out is recorded as a new call that names the one it repeats.

A value the redaction masked was never kept, so it is flagged and sent only if you type it again. A body that is not text goes out as it was recorded, unless only part of it was kept. Sending needs `dart:io`, so the web does not offer it.

## Configuration

```dart
await Flutwire.init(
  config: FlutwireConfig(
    retention: FlutwireRetention.oneDay,
    ignore: [FlutwireIgnore.host('analytics.example.com', subdomains: true)],
    redaction: const FlutwireRedaction(
      queryParameters: {'api_key'},
      bodyFields: {'password'},
    ),
  ),
);
```

Authorization headers and the values of cookies are masked by default; the names and attributes of cookies stay readable. A masked value is replaced when the call is recorded, so it never reaches memory, disk, a notification or an export. The other options are documented on `FlutwireConfig`: how much of a body is kept, where the history is stored, what the notification lists, the language, the look, and decoders for formats the inspector does not read, such as Protobuf.

## Test builds

A release build records nothing unless you say otherwise, because the history can hold tokens and personal data. To record in the builds you give to testers and in no other, pass the choice to `init`:

```dart
await Flutwire.init(
  config: FlutwireConfig(enabled: isTestBuild, allowInRelease: true),
);
```

Flutter cannot give one flavor a different set of dependencies, so the package is part of every build. Where `init` does not start it, it does nothing: no hook is installed, and on iOS and macOS the notification center stays with the app.

## Clients that bypass `dart:io`

`dart:io` does not exist on the web, and some clients bring a transport of their own. Three packages cover them.

| Package | Records |
| --- | --- |
| [`flutwire_dio`](https://pub.dev/packages/flutwire_dio) | Dio, through an interceptor |
| [`flutwire_http`](https://pub.dev/packages/flutwire_http) | `package:http`, through a client |
| [`flutwire_cloud_functions`](https://pub.dev/packages/flutwire_cloud_functions) | Firebase callable functions |

## What it does not do

Flutwire reads traffic and never changes it. It does not proxy other apps, and it cannot see what never passes through Dart: Firestore, Auth and Storage speak their own protocols through native SDKs. When a call may have gone unseen, because a client does not use `dart:io`, because an adapter ran in another isolate or because something replaced the capture, the inspector says so above the list and says what to change.

## More

The source, the roadmap and the issue tracker are in the [repository](https://github.com/NaCode-Studios/Flutwire). The package is Apache-2.0.
