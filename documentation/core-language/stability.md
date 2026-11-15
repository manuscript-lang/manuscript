+++
title = "What is frozen"
weight = 90
+++

# What is frozen

Versions are dates: `2026.11.0` is the first release of November 2026, and `2026.11.1` is its first patch. The month has no leading zero (`2026.1.0`), so every version is also valid semver. From 2026.11.0, these parts of Manuscript are frozen. A change that breaks one ships in the first release of a later month (`2026.12.0`, `2027.1.0`) and names its migration. A patch release never breaks them.

## Frozen

- Block and function syntax.
- Bindings: `:=` and `var`.
- Records and enums, and `match`.
- Optional and Result, with `?`.
- The one-owner rules: borrow by default, and `.clone()` as the only copy.
- `promise` and `wait`.
- `import` and `export`.
- The keys of `ms.toml`.
- The shapes of `--json` output.
- Diagnostic code numbers.

## Not frozen

- Standard library names outside core, strings, collections and files.
- The wording of error messages. The code number keeps its meaning.
- Anything about packages.

## When something is removed

Every removal from now on leaves an error that names the replacement, and keeps it for two releases that each start a new month. When the rewrite is mechanical, it also leaves a fix that `ms check --fix` applies, kept just as long. When the replacement depends on the program, such as moving the methods of an `impl` block, there is no fix and the error shows the new form.

The list of removed spellings is in [removed spellings](removed-spellings.md).
