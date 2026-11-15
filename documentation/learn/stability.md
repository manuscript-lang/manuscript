+++
title = "What is frozen before 1.0"
weight = 5
+++

# What is frozen before 1.0

From 0.1.0, these are the contracts that programs and scripts can rely on. A change that breaks one ships in a minor release (0.2, 0.3, and so on), states the old and new spelling, and the old spelling then fails with an error that names the new one. Patch releases (0.1.1, 0.1.2) never break them. From 1.0, a break needs a major release.

## Frozen

- **Syntax.** The grammar in the [language reference](../core-language/_index.md), including bindings (`:=`, `var`), `fn`, `type`, `enum`, `match`, `?` and `!`.
- **Ownership rules.** One owner per value, borrowing by default, `.clone()` as the only copy, and cleanup at the end of a scope.
- **Standard library names and signatures** that the [API reference](../standard-library/reference/_index.md) lists as public.
- **Command-line flags and exit statuses** of `ms`. A fault exits with 134, and a stack overflow or out of memory exits with 139, on every platform.
- **Diagnostic codes** (`MS` followed by digits) and the `--json` output formats, which carry a `format` number.
- **Project files.** The fields of `ms.toml`.
- **Archive names** on the releases page, `manuscript-rust-<os>-<arch>`, and the install script URLs.

## Not frozen

- The wording of an error message. The code keeps its meaning, the text may improve.
- Performance numbers, memory use, and the size of executables.
- Compiler and runtime internals, generated symbol names, and the layout of build caches.
- Executables built by one release are not promised to be byte for byte the same as another's.
- Anything marked experimental in its own documentation.

## When something is removed

A removed spelling does not stay silent. The compiler reports an error that names the replacement, and a check in the repository keeps that true. See [removed spellings](removed-spellings.md).
