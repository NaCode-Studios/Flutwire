# Changelog

## 1.0.1

Needs `flutwire` 1.0.1, which ends a call whose answer has no body when its head arrives: `FlutwireClient` used to leave such a call pending when the app never read the stream. The [repository changelog](https://github.com/NaCode-Studios/Flutwire/blob/main/CHANGELOG.md#101---2026-10-28) lists what the other packages gained.

## 1.0.0

`FlutwireClient` is final: it wraps another client and was not meant to be extended. Needs `flutwire` 1.0.0. The [repository changelog](https://github.com/NaCode-Studios/Flutwire/blob/main/CHANGELOG.md#100---2026-10-24) lists what the other packages gained.

## 0.2.0

When the client stands down for the `dart:io` capture it now tells Flutwire, so that Flutwire can say above the list when the capture never recorded the call, as happens with an inner client that does not use `dart:io`. Adds an example, and needs `flutwire` 0.2.0. The [repository changelog](https://github.com/NaCode-Studios/Flutwire/blob/main/CHANGELOG.md#020---2026-10-24) lists what the other packages gained.

## 0.1.0

First release. The [repository changelog](https://github.com/NaCode-Studios/Flutwire/blob/main/CHANGELOG.md#010---2026-10-24) lists what it contains.
