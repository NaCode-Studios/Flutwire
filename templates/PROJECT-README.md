<!--
  The README of the GitHub Project board (Project settings → README), not the repository README.
  This is where the board explains itself and where cross-project scheduling legitimately lives —
  the shared calendar is a real fact about the org, unlike a borrowed convention.
-->
# {{Name}}

The board for [`{{owner}}/{{Name}}`](https://github.com/{{owner}}/{{Name}}), {{one clause on what the library is}}.

This board is the plan of record: one item per milestone with its exit criterion, plus the day to
day of open issues, dependency bumps, and the decisions taken along the way. Each tier is also a
[milestone](https://github.com/{{owner}}/{{Name}}/milestones) in the repository, so the same
structure is readable without leaving the code.

The Status field is the shipped-state vocabulary, and nothing restates it elsewhere:

| Status | Means |
| --- | --- |
| `Planned` | Not started, no version assigned yet. |
| `In progress` | Merged under `[Unreleased]`, targeting the version in Target version. |
| `Shipped` | Released. Target version names the release, and it matches `CHANGELOG.md`. |
| `Post-1.0` | Deliberately deferred beyond `1.0`. |
| `Deferred` | Pushed to a later milestone. Decision note gives the reason. |
| `Declined` | Decided against. Decision note gives the reason. |

A milestone only becomes `Shipped` once the work sits under a released version heading in
`CHANGELOG.md`. Merged but unreleased is `In progress`.

## Why declined ideas are on the board

<!-- Name the actual rejected ideas and the argument that settled each one. This section is
     what stops the same suggestion being re-argued from scratch every few months. -->
{{what was considered and rejected, each with its reason}}

## Views

Roadmap board holds everything, grouped by status. Next up is the current queue ordered by Priority,
where `P0 · Next up` is the front. Shipped is the release history, each item naming its version.
Decisions and deferrals covers the rejected work. Timeline puts the dated work on a calendar, and
Maintenance collects dependency bumps, chores and bugs.

## Effort legend

`S` is hours to a day, `M` several days, `L` one or two weeks, `XL` multi-week.

## Positioning

{{What this library competes on, and what it deliberately does not. Several roadmap decisions
should only make sense against this rule — if none do, the rule is decoration.}}

{{Optionally: the one milestone that shapes the rest, and why.}}

## Sequencing across the organisation

{{The shared calendar: what this library gets, what it does not, and at whose expense. If work is
undated, say what it waits on — hardware, a signature, a decision, or capacity. Capacity is the one
that is easy to hide behind a vague "later", and hiding it is how a plan stops being a plan.}}

| Month | In flight | Background |
| --- | --- | --- |
| {{month}} | {{work}} | {{work}} |
