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

### Internal

- Dart workspace, strict analysis and CI over the Dart code and the Android and Apple builds (M1)

[Unreleased]: https://github.com/NaCode-Studios/Flutwire/commits/main
