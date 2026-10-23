# The library standard

What a NaCode Studios library looks like, on every surface, before it is considered set up. The point
is not uniformity for its own sake: it is that a reader who has seen one library already knows where
to look in the next one, and that no fact is written twice in two places that can disagree.

Two rules sit above the rest.

**Each fact has one home.** Versions live in `CHANGELOG.md`. The plan lives on the library's
board. The policy lives in `STABILITY.md`. Everything else links to them. A surface that restates a fact will
eventually contradict it.

**Adapt, never transplant.** These are the shapes and the vocabulary, not the prose. A library
explains itself in its own terms and links its own documents. Citing a sibling library to justify a
convention reads as borrowed authority — the convention should be stated where it belongs, once, and
referenced generically.

---

## 1 · Repository files

| File | Required | Owns |
| --- | --- | --- |
| `README.md` | always | The pitch, the honest status, and links out |
| `CHANGELOG.md` | always | What shipped, in which released version, on which date |
| `CONTRIBUTING.md` | always | Layout, ground rules, local setup |
| `LICENSE` | always | Apache-2.0 unless there is a reason |
| `STABILITY.md` | from `1.0` | Versioning, deprecation and support policy |
| `.editorconfig` | always | Editor settings that do not fight the formatter |
| `.github/workflows/` | always | CI over every toolchain the repo contains |
| `.github/FUNDING.yml` | always | Puts the Sponsor button on the repository |
| `.github/CODEOWNERS` | always | Who a pull request requests review from |
| `.github/dependabot.yml` | always | Weekly bumps per ecosystem, minor and patch grouped |
| `docs/brand/` | always | The brand kit — see §4 |
| `docs/<name>-hero.png` | always | The README banner, 2560×680 |

### README structure, in order

1. Hero banner (`docs/<name>-hero.png`), centred, full width.
2. `# Name`, then the tagline as a single bold sentence.
3. Badges: CI, License, then the language and ecosystem the library lives in. **Only badges that
   resolve** — no dead links to a package registry before publishing, no docs badge before docs.
4. Two or three paragraphs naming the problem concretely, and what is wrong with how it is solved
   today. Not features.
5. A short code sample that is representative rather than complete, and — where the library produces
   output a human reads — a sample of that output.
6. One sentence on what the library deliberately does **not** do.
7. A status blockquote: `> **Status — \`X.Y\`, <maturity>.**` then one sentence of context and a link
   to the board. Pre-`1.0`, say plainly that minors may break.
8. `## Why <name>` — three or four bold claims, each a paragraph, each falsifiable.
9. `## Architecture` — an ASCII tree, then a table of components and their roles.
10. `## Roadmap` — at most three labels (`Shipped (X.Y.Z)`, `Next`, `Later`), a paragraph each, ending
    in a link to the board and to the repository's milestones.
11. `## Building and testing`, `## Contributing`, `## License`.
12. `## Sponsor` — one sentence: `If <Name> is useful to you, consider [sponsoring NaCode
    Studios](https://github.com/sponsors/NaCode-Studios).` It exists so the Sponsor button and the
    README agree; a button with no matching line reads as an accident.

## 2 · Repository settings

- **Description** — one line, the shape `<what it is> — <three differentiators>`. It appears in
  search results and nowhere else does this job.
- **Homepage** — the project page. Set it only once the page exists; a badge or link to a 404 is
  worse than no link.
- **Topics** — all 20 GitHub allows, which is a target and not a limit. Topics are how a repository
  is found by subject rather than by name, so a slot left empty is a search that never reaches it.
  Choose the set from measured usage rather than from taste: `scripts/pick-topics.sh` reports how
  many public repositories carry each candidate, which separates a term the field uses from a term
  only this repository would apply to itself. Language, ecosystem and domain are the part that does
  not move. The rest are whatever the field is calling this work now, and that is why the ranking is
  **re-run at every minor release**: a set chosen once ages into the vocabulary of the year it was
  written, and the repository goes on answering searches nobody makes any more.
- **Social preview** — `docs/brand/<name>-social-preview.png`. Upload it under
  Settings → General → Social preview; there is no API for this.
- **`main` is protected** — pull requests only, no force-push, no deletion. On a private repository
  this needs a paid plan; if it is unavailable, say so rather than assuming it is on.
- **Sponsor button** — comes from `.github/FUNDING.yml`, which every repository created from the
  template already carries. The checkbox under Settings → Features must also be on, and GitHub
  Sponsors must be enabled for the organisation; the file alone renders nothing.

## 3 · The GitHub Project

One Project per library, public, titled with the plain library name — not "X Roadmap".

**Short description** — one or two sentences that name what this project is **and the one principle
or fact that governs its decisions**. It is read in a list next to every other project, so it has to
say something only this project could say. There is no formula, and reusing a sibling's sentence with
the name swapped is the specific thing to avoid — five identical descriptions carry the same
information as one.

What the existing ones do, as a guide to the register rather than a pattern to fill in: one names the
metric it is judged on, one names the evidence it is still missing, one names the scheduling rule
that orders it. Each is a claim you could argue with.

**Status update** — every project carries one, with `status`, `startDate`, `targetDate` and a body.
Without it the project shows no label in the list and reads as abandoned next to the ones that do.

- `ON_TRACK` — the work that matters has a path. `AT_RISK` — it has an unresolved dependency, whether
  that is evidence, a signature, hardware or hours. The label describes the goal, not whether this
  week's task is late.
- The body opens with **one sentence stating where things actually stand**, including the bad part.
  Then the specifics: what is done, what is scheduled, what is not, and what would change the plan.
- Dates are the project's window inside the shared calendar, not the sum of its milestones.

**Fields** — beyond the built-ins:

| Field | Type | Options |
| --- | --- | --- |
| `Status` | single select | `Planned` · `In progress` · `Shipped` · `Post-1.0` · `Deferred` · `Declined` |
| `Tier` | single select | The library's own tiers, plus `Maintenance` |
| `Area` | single select | The library's own subsystems |
| `Effort` | single select | `S` · `M` · `L` · `XL` |
| `Priority` | single select | `P0 · Next up` · `P1 · High` · `P2 · Medium` · `P3 · Low` |
| `Kind` | single select | `Milestone` · `Feature` · `Bug` · `Docs` · `Chore` · `Dependency` · `Release` |
| `Target version` | text | The version this lands in |
| `Exit criterion` | text | How you know it is done. One sentence, testable |
| `Decision note` | text | Required on `Deferred` and `Declined` |
| `Start date` | date | Only if the work is scheduled |
| `Target date` | date | Only if the work is scheduled |

`Status` and `Tier` are the only two fields whose options carry meaning across libraries. `Status`
is fixed by the vocabulary below. Everything else is per-library.

**Views** — six, in this order: `Roadmap board` (board), `Next up` (table), `Shipped` (table),
`Decisions & deferrals` (table), `Timeline` (roadmap), `Maintenance` (table).
`scripts/new-project.sh` creates them with the right names and layouts; filters, grouping and visible
columns are not settable through the API and must be configured once in the interface.

**Item titles** — `M# · Title`. A release item is `X.Y.Z · Title`. The board is the source: an
issue, a milestone or a README paragraph that disagrees with it is the thing that is wrong.

**Target version follows the tier.** A release never mixes tiers, so every milestone in a tier
carries the same target version and closing the tier cuts the tag. The tier-to-tag mapping lives in
the board's `Target version` field and is repeated in each milestone's description, so a reader
meets it in both places it is looked for. A tag is the thing you can check out to get the state the
board and the changelog were both describing, and a tier closed without one leaves that moment
unreachable.

**Every item carries an exit criterion.** A milestone whose done-ness is a matter of opinion is not a
milestone.

**Each tier is a milestone in the repository.** The board says where the project is going;
GitHub milestones make the same structure readable without leaving the repository, and give each tier
a completion count. One milestone per tier, titled exactly as the board's `Tier` option. A milestone
closes when the tier is released; work deferred out of a released tier moves forward to the next open
milestone rather than holding a finished one open.

**The shipped-state vocabulary.** Every surface that shows the state of a milestone uses exactly one
of these, and nothing else — no "Done", no "Complete", no bare tick:

| Token | Meaning |
| --- | --- |
| `Shipped` | Done and released. The `Target version` field names the version, and the same work appears under that version heading in `CHANGELOG.md` |
| `In progress` | Merged under `[Unreleased]`, or actively being built |
| `Planned` | Not started, no version assigned |
| `Post-1.0` | Deliberately deferred beyond `1.0` |
| `Deferred` | Pushed to a later milestone. Requires a decision note |
| `Declined` | Decided against. Requires a decision note |

The rule that matters: **an item is never `Shipped` without a released version behind it.** Merged but
unreleased is `In progress`.

**Dates are scheduling, not intent.** An item gets dates when it is actually in the calendar. Undated
work must say what it is waiting for — hardware, a signature, a decision, or capacity — and capacity
is the one that is easy to hide and must not be.

## 4 · Brand kit

`docs/brand/` holds, all named with the library prefix:

| File | Notes |
| --- | --- |
| `<name>-lockup-light.svg` / `-dark.svg` | The logo. Canvas tight to content — no phantom padding |
| `<name>-lockup-mono-light.svg` / `-mono-dark.svg` | One flat ink, `currentColor` |
| `<name>-symbol.svg` / `-symbol-mono.svg` | The mark alone. Never the logo |
| `<name>-favicon.svg` / `-light.svg` / `-favicon-512.png` | Favicon, avatar, app icon |
| `<name>-social-preview.png` | 2560×1280 |
| `<name>-tokens.css` | Colour, type, space, radius, elevation. Prefixed custom properties |
| `README.md` | Construction, minimum size, type, colour, and an explicit "don't" list |
| `../<name>-hero.png` | 2560×680 |

**Every SVG is self-contained.** Wordmarks are outlined to paths, so they render identically whether
or not the brand font is installed, and nothing references an external font, image or gradient. If a
glyph is missing from a font subset, fix the subset — never let the outliner skip it silently.

**Tokens are prefixed** — `--<xx>-` — so two kits can coexist on one page without collision.

## 5 · Order of operations

`scripts/new-library.sh` and `scripts/new-project.sh` do the mechanical parts. The order matters:

1. Create the repository from this template. Fill the templates in `templates/`.
2. Set the description, and rank the topics with `scripts/pick-topics.sh` before setting them. Leave
   the homepage until the page exists.
3. Build the brand kit. The hero and the social preview come last, because they quote the tagline.
4. Get CI green **before** the first substantive commit. A repository whose first ten commits are
   "fix CI" is a repository nobody trusts.
5. Create the Project, then configure the six views by hand.
6. Write the plan directly on the board, then create one milestone per tier in the repository and
   assign every issue to its tier. The board is written first and nothing restates it.
