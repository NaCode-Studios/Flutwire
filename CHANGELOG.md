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

### Internal

- Dart workspace, strict analysis and CI over the Dart code and the Android and Apple builds (M1)

[Unreleased]: https://github.com/NaCode-Studios/Flutwire/commits/main
