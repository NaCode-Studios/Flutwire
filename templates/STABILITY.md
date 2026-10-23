<!--
  Required from the 1.0 line onward. Before 1.0 a short note in the README status line is enough,
  and this file should not exist — an empty policy is worse than an admitted absence.
-->
# Stability policy

{{Name}} follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html). This document says what
that means in practice: what is covered, what is not, and how long a deprecated API survives.

## What is public

{{Which packages, namespaces or entry points are covered. Everything else — anything under a `src/`,
`internal` or `impl` path — may change in any release without notice, and depending on it is a
mistake this document does not protect.}}

## What a version bump means

| Change | Bump |
| --- | --- |
| Behaviour a caller can observe changes incompatibly | major |
| New capability, existing callers unaffected | minor |
| Fix that brings behaviour back to what was documented | patch |

{{Anything domain-specific that needs its own rule: wire formats, on-disk formats, generated code,
numerical output. Say explicitly whether the output of a computation is covered by SemVer — for
libraries that produce numbers, this is the question people actually need answered.}}

## Deprecation

A deprecated API survives at least {{N}} minor releases before removal, carries a deprecation notice
naming its replacement, and is listed under `Deprecated` in [`CHANGELOG.md`](CHANGELOG.md) in the
release that deprecates it.

{{If the library tracks an upstream project with its own policy, mirror that policy and say so —
promising longer than your dependency can deliver is a promise you will break.}}

## Supported versions

{{Which minor lines receive fixes, and for how long. "The latest minor" is a legitimate answer for a
one-person library, and a much better one than an implied promise of more.}}

## Platform and toolchain support

{{The minimum language, SDK and platform versions, and the rule for raising them — raising a minimum
is a {{major|minor}} change.}}
