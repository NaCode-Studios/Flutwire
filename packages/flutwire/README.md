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

The same builder lets the inspector dock. Choose "Dock beside the app" in its menu and it moves into a panel to the right of the app on a wide screen and under it on a phone, so the app and its traffic are in view together. Drag the strip between the two to resize it, or move the panel to the other side from its menu. Flutwire keeps the side and the size, and the next time the notification or the shortcut opens the inspector it docks again until "Open full screen" says otherwise.

## WebSockets and event streams

A WebSocket opened through `dart:io` is one call that stays open. Its Messages tab lists every message and control frame in the order it crossed, which way it went, how big it was and when, and a compressed message is shown after it is decompressed. An event stream (`text/event-stream`) lists its events as they complete, with their names and ids, and the raw stream stays the body of the response. Only the latest 1000 messages are kept, and the tab says how many came before them.

`dart:io` makes one client for all WebSockets the first time one is opened, so a WebSocket opened before `Flutwire.init` is not seen: call `init` first thing in `main`. On the web the browser opens WebSockets itself, and none is recorded there.

## Protobuf and MessagePack

A MessagePack body is shown as indented text with no setup, and a Protobuf body is shown by field number. To see Protobuf with names and types, give the decoder the descriptor set that `protoc` writes with `--descriptor_set_out=api.desc --include_imports`:

```dart
WidgetsFlutterBinding.ensureInitialized();
final descriptors = (await rootBundle.load('assets/api.desc')).buffer.asUint8List();

await Flutwire.init(
  config: FlutwireConfig(
    decoders: [FlutwireProtobufDecoder(descriptorSet: descriptors)],
  ),
);
```

A gRPC or gRPC-web call finds its message types from the method in its address. For any other Protobuf body, say which message it is with `messageType: (call, {required isRequest}) => 'demo.Person'`, and a body whose type is not known is shown by field number. The decoders run when a body is opened, so what the app sends and receives is not touched.

## Sending a call again

Open a call and tap the replay button in the top bar. The method, the address, the header fields and the body can all be changed, and Send makes the request. What goes out is recorded as a new call that names the one it repeats.

A value the redaction masked was never kept, so it is flagged and sent only if you type it again. A body that is not text goes out as it was recorded, unless only part of it was kept. Sending needs `dart:io`, so the web does not offer it.

## Comparing two calls

Long-press a call to select it, select a second one, and the compare button in the top bar sets them side by side: the status, the time, the query, the header fields and both bodies, with what differs marked and what is the same left out until you ask for it. JSON and XML are laid out before they are compared, so a change of indentation is not a difference. A call that was sent again compares with the call it repeats from its overview.

## Statistics and the timeline

The chart button in the top bar opens the statistics: how many calls went wrong, the average, the median and the 95th percentile of their times, the slowest calls, and how often the calls to each host fail. The Timeline tab lays the latest hundred calls on one time line, pale while a call waited for its first byte and solid while the answer came in, so calls that overlapped can be seen to. Calls from before a pause of two minutes are left out, so that yesterday's history does not squeeze today's calls into a corner. A call that was held at a breakpoint is counted but takes no part in the times, because it took as long as somebody looked at it. A WebSocket or an event stream takes no part in the times, because it stays open for as long as it has something to say.

## Calls from other isolates

Overrides belong to one isolate, so a call made with `Isolate.run` or `compute` is not seen unless the isolate takes part. `Flutwire.run` and `Flutwire.compute` stand in for the two and record what the isolate sends, with the redaction and the size limit of the app:

```dart
final todos = await Flutwire.run(() => fetchTodos());
final todo = await Flutwire.compute(fetchTodo, 'https://example.com/todos/1');
```

An isolate you start yourself calls `await Flutwire.attach()` before it uses the network. Where Flutwire is not recording, both are the plain `Isolate.run` and `compute`.

## Mocks and breakpoints

Everything above only reads traffic. Mocks and breakpoints change it, so they stay off until the app turns them on:

```dart
await Flutwire.init(config: const FlutwireConfig(interception: true));
```

A rule matches the address of a request, with `*` for any run of characters, as in `api.example.com/items/*`, and can be limited to one method. The newest rule that is switched on and matches decides what happens. "Mocks and breakpoints" in the menu of the inspector lists the rules and switches them on and off, and they are kept for the next run for as long as the history is.

A mock answers the request with a stored response and sends nothing. Open a call and choose "Mock this response" to start from what the server said, then change the status, the header fields or the body, or add a delay to make the server seem slow.

A breakpoint holds a request before it leaves, while the app waits for the answer, and opens it in the editor used for sending a call again. Send it on as it is or with changes, or stop it, and the app gets an error. A request that went out changed is recorded as a call that repeats the one the app made, and the first call ends as held. Switching a breakpoint off or deleting it sends on what it holds, as it was. Nothing has been recorded when the request is held, so the editor shows its real header fields, authorization included; the call that is recorded afterwards is masked as usual.

A line above the list says how many rules are in force and how many requests are held, and a call that a rule touched is marked in the list. Both work through the `dart:io` capture, so they cover Dio and `package:http` wherever `dart:io` exists and do nothing on the web or with `captureDartIo` off. A call made in another isolate is recorded but never mocked or held, and a mocked redirect is handed to the app as it is, not followed.

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

Authorization headers and the values of cookies are masked by default; the names and attributes of cookies stay readable. A masked value is replaced when the call is recorded, so it never reaches memory, disk, a notification or an export. The other options are documented on `FlutwireConfig`: how much of a body is kept, where the history is stored, what the notification lists, the language, the look, and decoders for formats the inspector does not read on its own.

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

Flutwire reads traffic and changes it only through the mocks and breakpoints the app turns on. It does not proxy other apps, and it cannot see what never passes through Dart: Firestore, Auth and Storage speak their own protocols through native SDKs. When a call may have gone unseen, because a client does not use `dart:io`, because an adapter ran in an isolate that never attached to Flutwire or because something replaced the capture, the inspector says so above the list and says what to change.

## More

The source, the roadmap and the issue tracker are in the [repository](https://github.com/NaCode-Studios/Flutwire). The package is Apache-2.0.
