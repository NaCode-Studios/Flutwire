# Stability policy

Flutwire follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html). This document says what that means in practice: what is covered, what is not, and how long a deprecated API survives. It complements [the project board](https://github.com/orgs/NaCode-Studios/projects/13), where the project is going, and [`CHANGELOG.md`](CHANGELOG.md), which says what has shipped.

The four packages, `flutwire`, `flutwire_dio`, `flutwire_http` and `flutwire_cloud_functions`, are released together under one version number, and each adapter asks for the major version of `flutwire` that it was released with.

## What is public

The public API is what a package exports from its main library: `package:flutwire/flutwire.dart`, `package:flutwire_dio/flutwire_dio.dart`, `package:flutwire_http/flutwire_http.dart` and `package:flutwire_cloud_functions/flutwire_cloud_functions.dart`. Every export names what it makes public, so nothing is public only because it shares a file with something that is.

Anything under a `src/` folder that those libraries do not export may change in any release, and so may a member annotated `@internal`, `@visibleForTesting` or `@protected`. The `@protected` ones are hooks for the subclasses inside the package, not for yours. Three more things are not covered, because they are made to be looked at and not called:

- The look, the wording and the languages of the inspector, and what the notification says.
- The example app, and the native code behind the notification.
- The exact text of the plain text and cURL exports. A cURL command that stops repeating the call it describes is a bug, but how it is quoted may change.

CI compares each package with its latest release on pub.dev and fails when the public API breaks and the version in the pubspec does not allow it. The comparison does not see a change of class modifier, such as a class that stops being extendable, or a change in behaviour, so those are held to this document and to review.

### How the types may be used

`FlutwireBodyDecoder` is the one interface meant to be implemented: write one to show a format the inspector does not know. It will not gain a member before the next major.

Everything else is for reading and constructing, not for implementing or extending. The model classes and the configuration are `final`, and `FlutwireStore` and `FlutwirePreferences` are `base`, so a minor release can add a member to any of them without breaking a program that compiled against the one before. A new value may be added to an enum in a minor release, so a `switch` over one wants a `default` case.

## What a version bump means

| Change | Bump |
| --- | --- |
| A public member is removed or renamed, a parameter or a type changes incompatibly, a class stops being usable the way it was, or a promise on this page stops holding | major |
| A public member is added, an option is added with a default that keeps today's behaviour, a new kind of call is recorded | minor |
| A fix that brings behaviour back to what was documented | patch |

Some promises are about behaviour and not about names. Recording does not change traffic: the calls an app makes and the answers it gets are the same with Flutwire and without it. Mocks and breakpoints are the one exception, and they stay off until `FlutwireConfig.interception` is turned on, which no release will do by default. The only requests Flutwire makes itself are the ones a person edits and sends again. A release build records nothing unless `allowInRelease` is set, and no release will change that default. With the default redaction, the values of `authorization`, `proxy-authorization`, `cookie` and `set-cookie` are masked when a call is recorded. A release may add a field to `FlutwireRedaction.defaultHeaders`, and none will take one out before the next major.

### What is written to disk and to a file

The history on disk has a layout, a number kept in a file called `layout` in its folder, and it is `1`. A folder with no such file is a new one, or one that 0.1.0 or 0.2.0 wrote, which has layout `1` as well. A release reads every layout up to its own. It does not change the layout in a minor or a patch: a field may be added to a summary, because a reader ignores what it does not know, and a field that a reader needs is not removed. A release that finds a layout newer than its own leaves the folder exactly as it is and keeps the history in memory, so going back to an older release never costs the history of a newer one. A new layout comes only with a major release, which reads the layout of the one before it.

The Flutwire JSON export carries `"flutwire": 1` at its top. A field may be added to it in a minor release, and none is removed or renamed before the next major, which is also the only release that changes that number. The HAR export follows HAR 1.2.

## Deprecation

A deprecated API survives at least two minor releases before removal, carries a deprecation notice naming its replacement, and is listed under `Deprecated` in [`CHANGELOG.md`](CHANGELOG.md) in the release that deprecates it. It is removed only in a major release.

## Supported versions

The latest minor release of the latest major receives fixes. An older minor does not: the answer to a bug in `1.2` is `1.3`.

## Platform and toolchain support

The packages need Dart 3.9 and Flutter 3.35, as their pubspecs say. CI runs the stable channel and, separately, the lowest versions of every dependency the constraints allow.

| Platform | What it gets |
| --- | --- |
| Android 7 (API 24) and later | The notification and the inspector |
| iOS 15 and later | The notification and the inspector |
| macOS 11 and later | The notification and the inspector |
| Windows and Linux | The inspector, opened by a floating button and a keyboard shortcut |
| Web | The same, with no `dart:io`, so calls are recorded by an adapter, and sending a call again, mocks and breakpoints are not offered |

The example app is built for Android, iOS, macOS and the web on every pull request. Windows and Linux need no native code, and their builds are not run.

Raising the minimum version of Dart, Flutter or one of those platforms is a minor release, and it is listed under `Changed` in [`CHANGELOG.md`](CHANGELOG.md).
