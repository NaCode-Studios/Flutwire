# library-template

The NaCode Studios standard for a library: what its repository contains, how its GitHub Project is
set up, and what its brand kit ships. Use it so a reader who has seen one library already knows where
to look in the next one.

**[`STANDARD.md`](STANDARD.md) is the specification.** Everything else here exists to make following
it quick.

## What is here

| Path | What it is |
| --- | --- |
| [`STANDARD.md`](STANDARD.md) | The spec: repository files, README structure, repo settings, Project fields and views, brand kit, and the order to do them in |
| [`templates/`](templates/) | Skeletons for `README`, `CHANGELOG`, `STABILITY`, `CONTRIBUTING`, the Project board README, and the brand kit README |
| [`scripts/new-project.sh`](scripts/new-project.sh) | Creates the Project with the house field set and the six views |
| [`scripts/set-repo-metadata.sh`](scripts/set-repo-metadata.sh) | Applies description, topics and homepage, and reports what still needs doing by hand |
| [`.editorconfig`](.editorconfig) | Editor settings. Adjust the per-language sections, keep the shape |

## Starting a library

```bash
gh repo create NaCode-Studios/NewLib --template NaCode-Studios/library-template --private
```

Then, in the order [`STANDARD.md`](STANDARD.md) §5 gives:

```bash
scripts/set-repo-metadata.sh NaCode-Studios/NewLib "one-line description" "topic,topic,..."
scripts/new-project.sh NewLib --tiers "Tier 0 · Foundations,Tier 1 · …" --areas "Core,Build & CI"
```

Fill the templates, delete `templates/`, `scripts/` and this README from the new repository, and keep
`STANDARD.md` out of it too — the standard lives here, not in every copy of it.

## The two rules that matter more than the files

**Each fact has one home.** Versions in `CHANGELOG.md`, the plan on the board, the policy in
`STABILITY.md`. Every other surface links to them. A fact written in two places is a fact that will
disagree with itself.

**Adapt, never transplant.** These are shapes and vocabulary, not prose. A library explains itself in
its own terms and links its own documents. Citing a sibling library to justify a convention reads as
borrowed authority — state the convention where it belongs, once, and reference it generically.

## What no API can do

Three things have to be done by hand, and the scripts say so rather than failing quietly:

- **View configuration.** `createProjectV2View` accepts a name and a layout and nothing else. Filters,
  grouping and visible columns are set once in the interface.
- **The social preview.** Upload it under Settings → General → Social preview.
- **Branch protection on a private repository.** It needs a paid plan. If it is unavailable, record
  that it is off instead of writing a contributing guide that implies a gate nobody is standing at.

## License

Apache-2.0. See [LICENSE](LICENSE).
