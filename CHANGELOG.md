# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Entries name the roadmap milestone they correspond to, e.g. `(M4)`, so a claim on the
board can be cross-checked against what actually shipped.

## [Unreleased]

### Added

- A call model with headers, bodies cut at a configurable limit with the real size kept, GraphQL operation detection, and redaction of header values, query values and body fields (M3)
- An in-memory history that keeps the newest calls inside a call count and a memory budget, and that pinned calls outlive (M3)

- Recording of every call made through `dart:io`, with no per-client setup: `package:http`, Dio's default adapter, Chopper, `Image.network` and anything else that builds an `HttpClient`, including redirects, failures, cancelled reads and multipart uploads (M4)

- A history kept on disk, so it survives a restart: one folder per app, a summary file and body files per call, bodies read back when a call is opened and released when memory runs short, retention of one hour, one day, one week or forever, a cap on the number of calls and on disk use, and pinned calls that nothing removes (M6)
- Export of calls as cURL, HAR 1.2, plain text and Flutwire JSON. A cURL command says when the body was cut or is binary instead of sending something different, and a multipart upload becomes `-F` fields (M7)

- A notification in the shade on Android that lists the latest calls, shows how many there are and how many went wrong, and has a Clear button. Tapping it opens the inspector, also when the app was not running. It asks for the notification permission when there is something to show, withdraws itself while the inspector is on screen, and needs no setup in the app (M8)

- The same notification on iOS and macOS. It lists the latest calls in the notification centre without a banner or a sound, updates in place, has a Clear action, and opens the inspector when tapped, also after the app was killed. It hands every other notification to the delegate the app already had (M9)

- `flutwire_dio` and `flutwire_http`: an interceptor and a client for the places the `dart:io` capture does not reach, above all the web. Next to the capture they stand down by themselves, so a call is never listed twice (M5)

- The inspector: a list of calls with search, filters for method and outcome, sorting and multi-select, a call in full with its timings, request and response, and two panes on a wide screen. It speaks English and Italian, has a look of its own in dark and light, and keeps the look the user picks in the settings (M10, M11, M13)
- A body viewer that shows content the way it wants to be read: a collapsible JSON tree, colour-coded XML, HTML and text, a form as a list of fields, a multipart upload as cards, images, and a hex dump for anything else, with search inside the body, copy, save, and a hook for decoders that teach it a format (M11)
- Share, save and copy: one call or many as text, cURL, HAR or JSON, and a body as a file (M12)
- An example app that makes every kind of call and builds for Android, iOS, macOS and the web (M14)

- `flutwire_cloud_functions`: Firebase callable functions, called by name or by URL, are listed with their payload, their result or error code, and how long they took. They go through the native SDK, so the `dart:io` capture cannot see them. The adapter sits on the Dart interface of the `cloud_functions` plugin, installs with one line and changes nothing for the app (M31)

### Internal

- Dart workspace, strict analysis and CI over the Dart code and the Android and Apple builds (M1)

[Unreleased]: https://github.com/NaCode-Studios/Flutwire/commits/main
