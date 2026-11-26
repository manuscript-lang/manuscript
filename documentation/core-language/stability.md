+++
title = "What is frozen"
weight = 90
+++

# What is frozen

Versions are dates: `2026.11.0` is the first release of November 2026, and `2026.11.1` is its first patch. The month has no leading zero (`2026.1.0`), so every version is also valid semver. From 2026.11.0, these parts of Manuscript are frozen.

## Frozen

- Block and function syntax.
- Bindings: `:=` and `var`.
- Text literals: `"..."` never interpolates, `f"..."` does, and `r"..."` is raw.
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

Every removal from now on leaves an error that names the replacement. When the rewrite is mechanical, it also leaves a fix that `ms check --only types --fix` applies. When the replacement depends on the program, such as moving the methods of an `impl` block, there is no fix and the error shows the new form.

The list of removed spellings is in [removed spellings](removed-spellings.md).
