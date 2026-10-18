+++
title = "Formatting"
weight = 1
+++

# Formatting

The formatter gives source one consistent layout.

## Format files or a project

```sh
ms fmt file.ms
ms fmt file.ms --check
ms fmt ms.toml --check
ms fmt ms.toml --check --json
ms fmt src test.ms
ms fmt src/*.ms --check
```

- Files are rewritten in place, keeping permissions. Invalid source gets diagnostics and is left unchanged; other files still format.
- `--check` writes nothing, lists every file needing changes in path order, and returns 1 if any file needs changes or fails.
- A manifest selects its entry, every `.ms` file below `source`, and `test.ms`/`*_test.ms`. A directory selects all `.ms` files recursively.
- Discovery skips hidden, `vendor`, and `node_modules` directories and directory symlinks; file symlinks must stay in the root. Explicit files can select excluded paths. Overlaps format once; an empty directory succeeds.
- Paths display relative to the invocation directory when inside it, otherwise absolute. See the [JSON contract](../implementation.md#machine-readable-checks-and-tests).

## Formatter contract

Formatting preserves meaning and comments, uses four-space indentation and LF endings with a final newline, and is idempotent. Rules:

- Keep token spellings; wrap only past 88 columns. Groups that fit stay on one line; wrapped lists pack simple elements into rows.
- Keep single-step blocks beside adjacent work; separate substantial blocks and guards with blank lines. Authored blank lines are discarded.
- Keep match arms together.
- One space around operators and after colons and commas; none next to delimiters; two before inline comments.
- Keep comment text, drop trailing whitespace, round comment-only indentation down to a multiple of four.

See the [complete layout rules](../implementation.md#linting-and-formatting). Rewrites are atomic renames in the same directory.

## Generated explanations

Compilation never invokes AI implicitly. Model output enters only through an explicit capability call and validation, and cannot change compilation or replace a source edit. See [source layout](../../core-language/basics/syntax.md).
