+++
title = "What is frozen before 1.0"
weight = 90
+++

# What is frozen before 1.0

From 0.1.0, these parts of Manuscript are frozen. A change that breaks one ships in a minor release (0.2, 0.3, and so on). Patch releases (0.1.1, 0.1.2) never break them. From 1.0, a break needs a major release.

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

Every removal from now on leaves two things behind, and keeps both for two minor releases:

- An error that names the replacement.
- A fix that `ms check --fix` applies.

The list of removed spellings is in [removed spellings](removed-spellings.md).
