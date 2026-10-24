# Changelog

## 1.0.0

The first stable release. The public API follows [Semantic Versioning](https://github.com/NaCode-Studios/Flutwire/blob/main/STABILITY.md), every export names what it makes public, and the history kept on disk records its layout, so that a release that does not know a layout leaves it alone. A Protobuf enum with a negative value shows by name, and a float shows its shortest digits. The [repository changelog](https://github.com/NaCode-Studios/Flutwire/blob/main/CHANGELOG.md#100---2026-10-24) lists what it contains, and what was removed or closed to implementing.

## 0.2.0

Adds editing a call and sending it again, the messages of a WebSocket and of an event stream, comparing two calls, statistics and a timeline, a dock beside the app, mocks and breakpoints, recording of the calls made in other isolates, and Protobuf and MessagePack bodies. On iOS and macOS the plugin no longer takes over the app's notification delegate in a build that never starts Flutwire. The [repository changelog](https://github.com/NaCode-Studios/Flutwire/blob/main/CHANGELOG.md#020---2026-10-24) lists what it contains.

## 0.1.0

First release. The [repository changelog](https://github.com/NaCode-Studios/Flutwire/blob/main/CHANGELOG.md#010---2026-10-24) lists what it contains.
