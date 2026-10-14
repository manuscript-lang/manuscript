+++
title = "Formatting"
weight = 1
+++

# Formatting

The source file defines the program. The formatter gives it a consistent layout, and tools can regenerate diagrams and explanations from it.

## Format files or a project

```sh
ms fmt file.ms
ms fmt file.ms --check
ms fmt ms.toml --check
ms fmt ms.toml --check --json
ms fmt src test.ms
ms fmt src/*.ms --check
```

Formatting writes each valid file in place, preserving its permissions. `--check` writes nothing, lists every file needing formatting in path order, and returns 1 if any file needs changes or any target fails. Invalid source produces diagnostics and is left unchanged; other selected files are still processed.

A manifest selects its entry, every `.ms` file below its configured source directory, and project `test.ms`/`*_test.ms` files. A directory recursively selects all `.ms` files. Both use the same discovery exclusions as project checking: hidden, `vendor`, and `node_modules` directories are skipped, and directory symlinks are not followed. Discovered file symlinks must stay within the selected root. Explicit file arguments can select excluded files; overlapping selections are formatted only once. An empty directory succeeds without output.

Explicit and discovered files use the same canonical display path: relative to
the invocation directory when inside it, otherwise absolute. `--check --json`
emits ordered file statuses and diagnostics, including a valid empty result.
See the [versioned JSON contract](../implementation.md#machine-readable-checks-and-tests).

## Formatter contract

Formatting preserves program meaning and comments. It uses four-space indentation and LF line endings with a final newline. Formatting twice produces the same text; this property is called idempotence.

The current formatter applies these layout rules:

- Keep token spellings; wrap expressions only when they exceed a soft limit of 88 columns; groups that fit stay on one line.
- Keep short lists and callback signatures compact, and preserve authored spacing between match arms.
- Put one space around operators and after argument/type colons and commas.
- Remove spaces next to delimiters and put two spaces before inline comments.
- Collapse blank runs to one line and remove leading and trailing blank lines.
- Keep comment text but remove trailing whitespace.
- Round comment-only indentation down to a multiple of four.

See the [complete layout rules](../implementation.md#linting-and-formatting) for continuation groups and paragraph boundaries. Golden-output and syntax-equivalence tests verify these choices. A valid rewrite replaces the file through an atomic rename in the same directory.

## Generated explanations

Compilation and task creation never invoke AI implicitly. Model output enters through an explicit capability call and validation. A generated explanation cannot change compilation behavior or replace a source edit.

See [source layout](../../core-language/basics/syntax.md) and [capability inputs](../../standard-library/services.md).
