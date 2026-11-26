+++
title = "Working with an agent"
weight = 9
+++

# Working with an agent

An agent writes the code and you read and steer it. This chapter sets the agent up, shows the loop it runs, and shows how you review what it did.

## Give the agent the skill

The skill is a short guide to writing Manuscript, with the language version it targets. It installs without the compiler, so an agent machine or a CI image can get it on its own:

```sh
curl -fsSL https://manuscript-lang.github.io/manuscript/install-skill.sh | sh
```

On Windows:

```powershell
irm https://manuscript-lang.github.io/manuscript/install-skill.ps1 | iex
```

It writes `manuscript/SKILL.md` and its references into `.claude/skills` and `.agents/skills`, and never overwrites an existing skill. Install it before the agent starts, so the agent loads it on its own. Each release also attaches `manuscript-skill.tar.gz`; set `MS_VERSION` to the release you want to take that version of the skill.

## The agent's loop

The agent writes `{totl}` in `invoice.ms` where it meant `{total}`. `ms check` names the problem, and applies the repair when it is mechanical:

```sh
ms check --only types invoice.ms --fix
```

```text
ms: applied 1 fix in 1 file
Checked invoice.ms
```

Every diagnostic reads `<cause>; <fix>`, so it says what is wrong and what to write instead. When a repair needs a decision about meaning, the message explains it and leaves the edit to the agent. `--json` returns the same diagnostics as data.

Three commands cover the rest:

- `ms search read file` finds a project or standard-library API and prints its signature, so the agent never needs the whole manual in context.
- `ms check --test` runs the checker, the formatter check, lint and tests, and returns one exit code. The agent loops until it is zero.
- `ms test --json` returns a failed test as data: kind, values, position and trace.

## You review the change

Instead of reading the diff top to bottom, start from what changed:

```sh
ms map ms.toml --format html -o code-map.html
git diff main | ms map --view review ms.toml --diff -
```

The code map is one offline file with source, types, calls and ownership side by side. `ms map --view review --diff` compares the checked program before and after the diff and ranks what to look at first: changed contracts, error flow and resource scopes.

![The Calls view of the code map, showing run calling run_command, with the three changed declarations listed in the sidebar](/images/code-map-calls.png "The Calls view for a changed program. Start from the outlined declarations and follow callers and callees.")

See [the interactive code map](../developer-tooling/implementation.md#interactive-code-map).

**Next:** [Standard library reference](../standard-library/reference/_index.md). **Exact rules:** [Commands for agents](../developer-tooling/implementation.md#commands-for-agents), [Diagnostics](../developer-tooling/source/diagnostics.md).
