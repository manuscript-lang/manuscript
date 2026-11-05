+++
title = "Commands and editor setup"
weight = 2
+++

# Commands and editor setup

Check and inspect the program an agent changed; save this as `review.ms`.

<!-- manuscript-example: {"mode":"run","stdout":"Ready to review\n","filename":"review.ms"} -->
```manuscript {filename="review.ms"}
export fn main() Int:
    print("Ready to review")
    return 0
```

```sh
ms check review.ms
ms fmt review.ms --check
ms run review.ms
```

```text
Checked review.ms
Ready to review
```

- Formatting succeeds silently; the example uses prelude `print` and returns its exit status.
- Manuscript is in alpha; syntax, APIs and tool output may change.

## Interactive code map

```sh
ms diagram review.ms --format html -o code-map.html
```

- Succeeds silently; open the file to follow checked source, types and calls offline.
- These are static relationships; [diff overlays](https://github.com/manuscript-lang/manuscript/blob/main/crates/ms-tooling/src/diagram.rs) mark source changes, not execution traces.

## Review report

Show the report summary in a POSIX terminal:

```sh
ms review review.ms | head -n 3
```

```text
MANUSCRIPT REVIEW REPORT  format 2
input   project (no diff)
result  1 modules, 1 entities
```

- The full report groups surface, effects, errors, resources and imports; it does not run tests.
- [Diff reports](https://github.com/manuscript-lang/manuscript/blob/main/crates/ms-tooling/src/review.rs) compare checked before/after source.

## Editor features

- Install the [VS Code extension](https://github.com/manuscript-lang/manuscript/tree/main/extensions/vscode#readme) and put `ms` on `PATH`.
- Other LSP clients launch `ms lsp`; use hover, definitions and references to inspect checked code.

<span id="choose-the-next-command"></span>
<span id="rebuild-on-save"></span>
<span id="source-inspection"></span>
<span id="commands-for-agents"></span>
<span id="selecting-independent-analysis-inputs"></span>
<span id="machine-readable-native-results"></span>
<span id="machine-readable-checks-and-tests"></span>
<span id="linting-and-formatting"></span>
<span id="debugging-and-profiling"></span>

Next: [command options](https://github.com/manuscript-lang/manuscript/blob/main/crates/ms-cli/src/help_text.rs), [CLI selection rules](https://github.com/manuscript-lang/manuscript/blob/main/crates/ms-cli/src/invocation.rs), [JSON command results](https://github.com/manuscript-lang/manuscript/tree/main/crates/ms-cli/src/engine), [formatting](source/formatting.md) and [profiling](debugging/debugger-integration.md).
