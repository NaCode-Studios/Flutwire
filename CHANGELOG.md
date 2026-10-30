# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Entries name the roadmap milestone they correspond to, e.g. `(M4)`, so a claim on the
board can be cross-checked against what actually shipped.

## [Unreleased]

## [1.0.2] - 2026-10-30

### Fixed

- On iOS and macOS, a notification that was not Flutwire's closed the app when it was tapped, or when it arrived with the app open, if the app also had Firebase Messaging or another plugin that passes calls on to the delegate it replaces. It happened from the second launch of a build, when the plugin takes the notification center at registration and again when Dart starts. In between, Firebase Messaging takes the center and keeps the plugin as the delegate to pass calls on to, so the second time the plugin remembered Firebase Messaging as its previous delegate, and each handed the call back to the other until the stack ran out. The plugin now keeps every delegate it replaces and hands a call to the newest one that the call has not reached yet. A delegate that hands the call back gets the next one down, none gets the same call twice, and the app's own delegate is reached as before

### Internal

- The Apple job in CI compiles the chain that keeps those delegates and runs it against a model of the three delegates that met in the crash, in each order in which they can take the center. It is the first check of the Swift half other than building it

## [1.0.1] - 2026-10-28

### Fixed

- A call whose answer has no body stayed pending, with a duration that kept growing, when the app never read the answer, as it does not after looking at the status of a conditional request. The call now ends when the head arrives, for the answer to a HEAD request, a 204, a 304 and an answer that says it is empty. A redirect still waits, because the client may follow it
- The recording dot, and the status and the time of a call that is still running, pulsed for as long as they were on screen, which kept the app drawing a frame on every refresh with nothing else changing. A pulse now beats three times when it appears, the recording dot beats again when the history changes, and then it holds still. It also no longer starts when the system asks for reduced motion, where it ran without being seen

### Internal

- The release workflow looks up the archive of each package by the version of the tag, for the attestation and for the record on the Packages panel. It used the latest version that pub.dev lists, which can still be the previous one for minutes after an upload, and on 1.0.0 it was for two of the four packages when the record job read it

## [1.0.0] - 2026-10-24

### Added

- A stability policy, `STABILITY.md`. It says what is public, what a version bump means for the API, the history on disk and the JSON export, how long a deprecated member stays, which versions get fixes, and which platforms and toolchains are supported. It also holds three promises about behaviour: recording does not change traffic unless `interception` is turned on, a release build records nothing unless it is asked to, and the default redaction masks credentials (M25)
- The history on disk records its layout in a file called `layout`. A folder with none is a new one, or one that 0.1.0 or 0.2.0 wrote, and is read as layout 1. A folder with a layout this release does not know is left exactly as it is while the history is kept in memory, where an older release would have deleted every summary it could not read (M40)
- A second tour in the README, with a 74 second video, and four more screenshots on the pub.dev page of `flutwire`, for what 0.2.0 added: two calls compared, the statistics, the dock, and the mocks and breakpoints with the marks they leave on the list. The page now shows ten screenshots, with the light list and the XML body making room (M37)

### Changed

- Every export of a package names what it makes public. `parseFormEncoded` and `prettyXml` were exported with the body model by accident and no longer are: `FlutwireBody.formFields` and `FlutwireBody.prettyText` are how to reach what they do (M25)
- `FlutwireCallRecorder.observeRequest` is removed. Nothing called it, and a client that has a request body as a stream reports it with `requestBody` (M25)
- `FlutwireStore`, `MemoryFlutwireStore` and `FlutwirePreferences` are `base` classes, so none can be implemented outside the package, and `FlutwireClient` in `flutwire_http` is `final`. None was meant to be implemented or extended by an app, and each can now gain a member without breaking one. `FlutwireBodyDecoder` stays an interface to implement. The API comparison does not see a change of class modifier, so it is listed here (M25)
- `FlutwireExportFormat.render` writes this package's version as the creator of a HAR where it wrote `0` (M25)
- On a screen narrower than 600 logical pixels the docked inspector always sits under the app, and its menu does not offer the right side there, because beside the app it left neither of them a usable width (M39)

### Fixed

- A Protobuf enum with a negative value showed as a number instead of its name, because a descriptor writes such a value as ten bytes and the reader dropped it (M38)
- A Protobuf float showed the 17 digits of the double it widens to, `0.10000000149011612` for `0.1`. It shows the shortest decimal that reads back as the same float (M38)
- The four numbers above the list ran into each other in a narrow panel and at a large text size. They stand in two rows of two when four do not fit, and the title of a selection shrinks to the room the buttons leave instead of being cut off (M39)

### Internal

- CI compares the public API of each package with its latest release on pub.dev, and fails when the API breaks and the pubspec has not moved to a version that allows it (M41)
- CI builds the example for the web, which no job did before (M39)
- The Protobuf decoder is tested against a descriptor set and messages that `protoc` and the code it generates wrote. Its other tests build their input by hand (M38)
- A history written by the 0.2.0 code, with a summary in the 0.1.0 shape, is read back in a test (M40)
- `integration_test/features_smoke_test.dart` records a call through `dart:io` and opens the comparison, the statistics and the dock on the platform it is started on. It was run on macOS and on an iOS simulator, and the example was run by hand on the web (M39)
- The example adds no button of its own where Flutwire floats one, so on the web the two no longer overlap (M39)

## [0.2.0] - 2026-10-24

### Added

- Any call can be opened in an editor, changed and sent again. The editor starts from the method, address, header fields and body that were recorded. A value the redaction masked was never kept, so it is flagged and not sent unless it is typed again. What goes out is recorded as a new call that names the one it repeats, marked in the list and linked from its overview. It needs `dart:io`, so the web does not offer it (M15)
- WebSockets and server-sent event streams. A WebSocket is one call that stays open, and it lists its messages with the ping, pong and close frames, which way each went, how big it was and when it crossed, compressed messages included. An event stream lists its events as they complete, with their names and ids, and keeps the raw stream as the body of the response. Both get a Messages or Events tab, a badge in the list, a line in the overview, entries in the HAR and text exports, and their messages are kept on disk with the call. The latest 1000 messages are kept, with a megabyte of payload at most, and the tab says how many came before (M16)
- Two calls can be compared side by side. Select two calls and the compare button in the top bar opens them with the overview, the query parameters, the header fields and the bodies of both, and what differs is marked: a changed line is paired with the new one and the part of it that changed is highlighted, a field only one side has says so, and what is the same is left out until you ask for it. JSON and XML are laid out before they are compared, a form is compared field by field, and a body that is not text is compared as bytes. A call that was sent again compares with the call it repeats from its overview (M17)
- A response can be mocked and a request can be held before it leaves. With `FlutwireConfig(interception: true)`, a rule matches the address of a request, with `*` for any run of characters, and can be limited to one method. A mock answers with a stored response and sends nothing: "Mock this response" on any call starts from what the server said, and the status, the header fields, the body and a delay can be changed. A breakpoint holds the request while the app waits and opens it in the editor used for sending a call again, where it is sent on as it is or changed, or stopped, and the app gets an error. A request that went out changed is recorded as a call that repeats the one the app made, and switching a breakpoint off or deleting it sends on what it holds. The rules are listed in the inspector's menu, switched on and off one by one and kept for the next run, a line above the list says how many are in force and how many requests are held, and a call that a rule touched is marked in the list. It works through the `dart:io` capture, so it has no effect on the web. Interception is off by default because it is the first thing Flutwire does that changes traffic (M18)
- Calls made in another isolate reach the history of the app. `Flutwire.run` and `Flutwire.compute` stand in for `Isolate.run` and `compute` and record what the isolate sends, with the redaction and the size limit of the app. An isolate you start yourself calls `Flutwire.attach()` first, and the call is put in the history under an id of the main isolate's own. The note about an adapter that ran in an isolate that did not attach now says what to do about it (M19)
- Statistics for the history, from a button in the top bar. A summary gives the number of calls, how many went wrong and the error rate, the average, the median and the 95th percentile of the times and the bytes that moved. It lists the ten slowest calls and ranks the hosts by how often their calls fail. A timeline lays the latest hundred calls on one time line, from after the latest pause of two minutes, with the wait for the first byte apart from the answer coming in, and says how many calls were in flight at once. A WebSocket, an event stream or a call held at a breakpoint takes no part in the times, so the average in the list no longer counts one either (M20)
- The inspector can sit in a panel beside the app, so that the app and its traffic are in view together. "Dock beside the app" in its menu moves it to the right of the app on a wide screen and under the app on a phone, the strip between the two resizes it, and the menu moves it to the other side or takes it back to the full screen. The app is laid out in the room that is left and keeps its state, the panel has a navigator of its own so that a call opens inside it, and the side and the size are kept for the next run. It needs `Flutwire.builder` in the app, which the web and desktop already use for the floating button (M21)
- Protobuf and MessagePack bodies are readable. MessagePack needs nothing and is shown as indented text, and a Protobuf body with no schema is shown by field number, guessed the way `protoc --decode_raw` guesses. `FlutwireProtobufDecoder` takes the descriptor set that `protoc` writes and shows the fields by name and type, with enums by name, maps as objects and packed runs as lists. A gRPC or gRPC-web call finds its message types from the method in its address, lists the messages of a stream and shows the trailers. The decoders run when a body is opened, so the capture is untouched. The example app has a body of each (M22)
- A line above the list that says when Flutwire may be missing calls, with the reason and what to change: a client or adapter that does not use `dart:io`, an adapter that ran in another isolate, or something that replaced the capture's `HttpOverrides`. It stays out of sight until Flutwire has seen one of them happen, and it names the client or the isolate. `Flutwire.coverage` lists the notes, and an adapter that stands down for the capture reports through `Flutwire.watchStandDown`. The example app has a probe for each case (M24)
- An example for each adapter, so the package page on pub.dev has one to show (M34)
- A demo video, a tour of four screens and eight screenshots from the example app on an Android emulator, in the README and on the pub.dev page of `flutwire`, and a diagram of how a call travels in the README (M36)

### Fixed

- `flutwire_dio` allowed `dio` 5.0 and 5.1 but does not compile against them, because `DioException` arrived with 5.2. The constraint is now `^5.2.0` (M34)
- On iOS and macOS the plugin took over the app's notification delegate as soon as the app launched, in every build, whether or not the app ever started Flutwire. An app that keeps Flutwire in its production build with `init` switched off now keeps its own notification handling untouched: the plugin waits until Flutwire has run in that build, and remembers it did so that a tap on the notification after the app was killed still finds the delegate in place. It also passes the call that opens the system's notification settings on to the delegate it replaced, which it did not before

### Internal

- CI checks that every package passes `flutter pub publish --dry-run`, and that it analyzes and passes its tests at the lowest versions its constraints allow, each package resolved on its own (M34)
- The release workflow publishes the four packages to pub.dev, the core first and the adapters once the core can be resolved. It holds no token, because pub.dev trusts the repository and the tag, the third-party actions it runs are pinned to a commit, and it attests and records each archive (M35)
- The Apple build runs on every pull request instead of waiting for it to leave draft, now that the repository is public

## [0.1.0] - 2026-10-24

### Added

- A call model with headers, bodies cut at a configurable limit with the real size kept, GraphQL operation detection, and redaction of header values, query values and body fields. Cookie headers keep their names and attributes and lose only their values (M3)
- An in-memory history that keeps the newest calls inside a call count and a memory budget, and that pinned calls outlive (M3)
- Recording of every call made through `dart:io`, with no per-client setup: `package:http`, Dio's default adapter, Chopper, `Image.network` and anything else that builds an `HttpClient`, including redirects, failures, cancelled reads and multipart uploads (M4)
- A history kept on disk, so it survives a restart: one folder per app, a summary file and body files per call, bodies read back when a call is opened and released when memory runs short, retention of one hour, one day, one week or forever, a cap on the number of calls and on disk use, and pinned calls that nothing removes (M6)
- Export of calls as cURL, HAR 1.2, plain text and Flutwire JSON. A cURL command says when the body was cut or is binary instead of sending something different, and a multipart upload becomes `-F` fields (M7)
- A notification in the shade on Android that lists the latest calls, shows how many there are and how many went wrong, and has a Clear button. Tapping it opens the inspector, also when the app was not running. It asks for the notification permission when there is something to show, withdraws itself while the inspector is on screen, and needs no setup in the app (M8)
- The same notification on iOS and macOS. It lists the latest calls in the notification centre without a banner or a sound, updates in place, has a Clear action, and opens the inspector when tapped, also after the app was killed. It hands every other notification to the delegate the app already had (M9)
- `flutwire_dio` and `flutwire_http`: an interceptor and a client for the places the `dart:io` capture does not reach, above all the web. Next to the capture they stand down by themselves, so a call is never listed twice (M5)
- The inspector: a list of calls whose search reads URLs, status codes, GraphQL operations, headers and the text of bodies, with filters for method and outcome, sorting and multi-select, a call in full with its timings, request and response, and two panes on a wide screen. It speaks English and Italian, has a look of its own in dark and light, and keeps the look the user picks in the settings (M10, M11, M13)
- A cookie view: the cookies a call sent and the cookies it set, with their attributes. Their values are hidden like any other credential (M23)
- A floating button and the Ctrl or Cmd with Shift and L shortcut that open the inspector where there is no notification to tap: the web, Windows and Linux (M13)
- A body viewer that shows content the way it wants to be read: a collapsible JSON tree, colour-coded XML, HTML and text, a form as a list of fields, a multipart upload as cards, images, and a hex dump for anything else, with search inside the body, copy, save, and a hook for decoders that teach it a format (M11)
- Share, save and copy: one call or many as text, cURL, HAR or JSON, and a body as a file (M12)
- An example app that makes every kind of call and builds for Android, iOS, macOS and the web (M14)
- `flutwire_cloud_functions`: Firebase callable functions, called by name or by URL, are listed with their payload, their result or error code, and how long they took. They go through the native SDK, so the `dart:io` capture cannot see them. The adapter sits on the Dart interface of the `cloud_functions` plugin, installs with one line and changes nothing for the app (M31)

### Internal

- Dart workspace, strict analysis and CI over the Dart code and the Android and Apple builds (M1)
- The brand kit, the README and a contrast test that keeps every text and status colour at 4.5 to 1 on its surface (M2)
- A README and a changelog in each of the four packages, so the page of each one says what it records and when it is needed (M32)
- A release workflow that runs the same jobs as every pull request against a tag and creates the GitHub Release from this changelog (M32)
- A test that measures the JSON tree on a device, in profile mode, with a 200 KB response in two shapes: opening it, scrolling, collapsing and expanding it, and searching inside it (M11)
- The screens of the inspector work on an injected session instead of reading a global, which lets them be tested against a fake (M33)
- Analysis rules for open subscriptions and sinks, dropped futures, catch clauses that name no type, positional booleans and dynamic calls (M33)

[Unreleased]: https://github.com/NaCode-Studios/Flutwire/compare/v1.0.2...HEAD
[1.0.2]: https://github.com/NaCode-Studios/Flutwire/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/NaCode-Studios/Flutwire/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/NaCode-Studios/Flutwire/compare/v0.2.0...v1.0.0
[0.2.0]: https://github.com/NaCode-Studios/Flutwire/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/NaCode-Studios/Flutwire/releases/tag/v0.1.0
