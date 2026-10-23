# Contributing

<!-- Open with the honest state of the project. A pre-alpha repo should say so here too. -->
{{One or two sentences: how settled the architecture is, and whether to open an issue before
writing code.}}

## Layout

| Path | What lives there |
| --- | --- |
| `{{path}}` | {{what belongs there, and what does not}} |

## Ground rules

<!-- The invariants a reviewer will actually reject a pull request over. Two to four.
     Each one states the rule and why it exists, because a rule without a reason gets
     argued with on every pull request. -->
**{{rule}}** {{why, and what breaking it costs}}

**{{rule}}** {{…}}

## Local setup

```bash
{{install}}
```

```bash
{{the checks CI runs, so a contributor can go green before pushing}}
```

## Commits and branches

`main` is protected; work on a branch and open a pull request. Keep commits scoped to one change and
write the message in the imperative mood.

<!-- If main is not actually protected — a private repository without a paid plan cannot be —
     say that here instead of implying a gate that does not exist. -->
