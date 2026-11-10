+++
title = "Formatting"
weight = 1
+++

# Formatting

Let `ms fmt` handle spacing and line wrapping so you can focus on the program. Use its check mode before sharing a change to find formatting drift without rewriting files.

## Format one file

Save this valid but unevenly spaced program as `format.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"5\n"} -->
```manuscript
export fn main() Int:
    total:=2+3
    print(total)
    return 0
```

```sh
ms fmt format.ms --check
```

```text
Formatting needed: format.ms; run ms fmt format.ms to rewrite it
```

The check exits with status 1 and leaves the file unchanged. Apply the formatting, then check again:

```sh
ms fmt format.ms
ms fmt format.ms --check
```

Both commands now succeed silently. The assignment becomes `total := 2 + 3`; running the program still prints `5`.

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
- Keep single-step blocks beside adjacent work; separate substantial blocks and guards with blank lines. Authored blank lines are discarded, except one kept after a comment-only line so a comment block stays apart from the next comment or declaration.
- Keep match arms together.
- One space around operators and after colons and commas; none next to delimiters; two before inline comments.
- Keep comment text, drop trailing whitespace, round comment-only indentation down to a multiple of four.

See the [complete layout rules](../implementation.md#linting-and-formatting). Rewrites are atomic renames in the same directory.
