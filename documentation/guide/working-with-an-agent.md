+++
title = "Working with an agent"
weight = 9
+++

# Working with an agent

Manuscript assumes that an agent often writes the code and a person reads and steers it. The toolchain gives both sides something to work with. This chapter follows one change from the first mistake to a reviewed pull request.

## The agent makes a typo

The agent writes `{totl}` where it meant `{total}`. `ms check` names the problem, and when the repair is mechanical it applies it:

```sh
ms check invoice.ms --fix
```

```text
ms: applied 1 fix in 1 file
Checked invoice.ms
```

Every diagnostic reads `<cause>; <fix>`, so a message states what is wrong and what to write instead. When a repair needs a decision about meaning, the message explains it and leaves the edit to the agent. `ms check invoice.ms --json` returns the same diagnostics as data.

## The agent finds its way

An agent does not need the whole manual in its context.

- `ms guide` prints a compact cheat sheet of the language.
- `ms search_symbol read file` finds a project or standard-library API and prints its signature in bounded output.
- `ms verify` runs the checker, the formatter check, lint and tests, and returns one exit code. The agent loops until it is zero.

When a test fails at run time, `ms test --json` returns the fault as data: kind, values, position and trace.

## A person reviews the change

Instead of reading the diff top to bottom, start from what changed:

```sh
ms diagram ms.toml --format html -o code-map.html
git diff main | ms review ms.toml --diff -
```

The code map is one offline file with source, types, calls and ownership side by side. `ms review --diff` compares the checked program before and after the diff and ranks what to look at first: changed contracts, error flow and resource scopes. ![The Calls view of the code map, showing run calling run_command, with the three changed declarations listed in the sidebar](/images/code-map-calls.png "The Calls view for a changed program. Start from the outlined declarations and follow callers and callees.")

See [the interactive code map](../developer-tooling/implementation.md#interactive-code-map).

## Finding and fixing problems on purpose

Manuscript itself is built this way, and the same workflows fit your project.

- **Bug bash.** Pick one area. An agent writes small probe programs aimed at new features and their edges, compares the results with the documented rules, fixes real bugs with a regression test, and files an issue with a minimal repro for anything that needs a decision. The workflow is the [`bug-bash` skill](https://github.com/manuscript-lang/manuscript/blob/main/skills/bug-bash/SKILL.md).
- **Perf bash.** Start from a measured gap. The agent reproduces it on a release build, measures before changing, fixes it in the right layer, and shows before and after on the same machine. `ms profile` gives it folded stacks and a top report. The workflow is the [`perf-bash` skill](https://github.com/manuscript-lang/manuscript/blob/main/skills/perf-bash/SKILL.md).

Both skills are written for work on the Manuscript compiler and standard library, and they show the shape of the loop: probe, measure, fix with a test, and write down the result.

**Next:** [Standard library reference](../standard-library/reference/_index.md). **Exact rules:** [Commands for agents](../developer-tooling/implementation.md#commands-for-agents), [Diagnostics](../developer-tooling/source/diagnostics.md).
