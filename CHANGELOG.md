# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Entries name the roadmap milestone they correspond to, e.g. `(M4)`, so a claim on the
board can be cross-checked against what actually shipped.

## [Unreleased]

### Added

- Any call can be opened in an editor, changed and sent again. The editor starts from the method, address, header fields and body that were recorded. A value the redaction masked was never kept, so it is flagged and not sent unless it is typed again. What goes out is recorded as a new call that names the one it repeats, marked in the list and linked from its overview. It needs `dart:io`, so the web does not offer it (M15)
- A line above the list that says when Flutwire may be missing calls, with the reason and what to change: a client or adapter that does not use `dart:io`, an adapter that ran in another isolate, or something that replaced the capture's `HttpOverrides`. It stays out of sight until Flutwire has seen one of them happen, and it names the client or the isolate. `Flutwire.coverage` lists the notes, and an adapter that stands down for the capture reports through `Flutwire.watchStandDown`. The example app has a probe for each case (M24)
- An example for each adapter, so the package page on pub.dev has one to show (M34)
- A demo video, screenshots and two diagrams in the README and on the pub.dev page of `flutwire`, taken from the example app running on a device (M36)

### Fixed

- `flutwire_dio` allowed `dio` 5.0 and 5.1 but does not compile against them, because `DioException` arrived with 5.2. The constraint is now `^5.2.0` (M34)

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

[Unreleased]: https://github.com/NaCode-Studios/Flutwire/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/NaCode-Studios/Flutwire/releases/tag/v0.1.0
