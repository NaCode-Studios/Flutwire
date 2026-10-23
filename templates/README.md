<!--
  Repository README skeleton. Replace every {{PLACEHOLDER}} and delete the comments.
  The order of sections is fixed by STANDARD.md §1 — the prose is not.
  Write about this library only. Do not cite a sibling library to justify a convention.
-->
<p align="center">
  <img src="docs/{{name}}-hero.png" alt="{{Name}} — {{tagline}}" width="100%">
</p>

# {{Name}}

**{{One bold sentence. What it does, or what it lets you stop worrying about.}}**

<!-- Only badges that resolve today. No registry badge before you publish. -->
[![CI](https://github.com/{{owner}}/{{Name}}/actions/workflows/ci.yaml/badge.svg)](https://github.com/{{owner}}/{{Name}}/actions/workflows/ci.yaml)
[![License](https://img.shields.io/badge/license-Apache%202.0-{{inkHex}}?labelColor={{groundHex}})](LICENSE)
[![{{Language}}](https://img.shields.io/badge/{{Language}}-{{version}}-{{accentHex}}?logo={{logo}}&logoColor=white&labelColor={{groundHex}})]({{languageUrl}})

<!--
  Two or three paragraphs. Name the problem concretely and say what is wrong with
  how it is solved today. Not a feature list — a reader should recognise their own
  pain in the first sentence.
-->
{{problem}}

{{what this library does about it}}

```{{lang}}
{{a representative sample — not a complete program}}
```

<!-- If the library prints something a human reads, show that too. It is the product. -->
```
{{sample output}}
```

{{One sentence on what this library deliberately does not do.}}

> **Status — `{{X.Y}}`, {{maturity}}.** {{One sentence of context.}}
> The [board]({{board_url}}) is the plan of record and tracks it milestone by milestone.
> {{Pre-1.0: say plainly that minor versions may break.}}

## Why {{Name}}

<!-- Three or four claims. Each one a bold lead and a paragraph. Each one falsifiable. -->
**{{claim}}** {{why it is true, and what it costs}}

**{{claim}}** {{…}}

**{{claim}}** {{…}}

## Architecture

```
{{ascii tree — modules, and which way the dependencies point}}
```

| {{Component}} | Role |
| --- | --- |
| `{{name}}` | {{one line}} |

## Roadmap

**{{Shipped (`X.Y.Z`)}}** — {{a paragraph, not a list}}

**Next** — {{a paragraph}}

**Later** — {{a paragraph}}

The [board]({{board_url}}) carries the milestone plan and its exit criteria, and every tier is a
[milestone](https://github.com/{{owner}}/{{Name}}/milestones) in this repository.

## Building and testing

```bash
{{the commands CI runs, in the order CI runs them}}
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). {{The two or three rules that shape everything else.}}

Brand assets and design tokens live in [`docs/brand/`](docs/brand/).

## License

Apache-2.0. See [LICENSE](LICENSE).

<!-- Keep this in step with .github/FUNDING.yml: the button and the prose must agree. -->
## Sponsor

If {{Name}} is useful to you, consider [sponsoring NaCode Studios](https://github.com/sponsors/NaCode-Studios).
