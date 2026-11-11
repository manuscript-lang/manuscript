---
name: manuscript
description: Write, check, test, and revise idiomatic Manuscript programs. Use for .ms source, Manuscript APIs, ownership, errors, streams, and compiler diagnostics.
---

# Write Manuscript

Generated for Manuscript {{MS_VERSION}}. Compare with `ms --version`; regenerate this skill with the matching compiler when stale. Manuscript is in alpha: syntax and APIs may change.

## Defaults

Use four-space indents, `:=` for immutable locals, `var` for mutation, and explicit named-function types. Prefer early returns and short pipelines. Handle Results with `?` or explicit branches; clone only for an independent owner.

## References

- [Program structure](references/program-structure.md) covers modules, imports and main. Shows indentation, types and receiver methods. Read when structuring a program.
- [Values and control](references/values-and-control.md) covers bindings and literals. Shows branches, loops and range bounds. Read when writing computations.
- [Types and functions](references/types-and-functions.md) covers signatures, generics and callbacks. Shows enums and interfaces. Read when designing reusable operations.
- [Errors and optionals](references/errors-and-optionals.md) separates absence from failure. Shows propagation and explicit handling. Read before using fallible APIs.
- [Ownership and cleanup](references/ownership-and-cleanup.md) explains borrows, moves and clones. Shows mutation and cleanup. Read when storing values or managing resources.
- [Collections and pipelines](references/collections-and-pipelines.md) covers construction, lookup and mutation. Distinguishes method and function pipelines. Read when transforming data.
- [Effects and concurrency](references/effects-and-concurrency.md) covers effects, promises and streams. Explains waiting and capture rules. Read before concurrent or streaming work.
- [Validation](references/validation.md) covers checks, tests and diagnostics. Includes a complete assertion. Read before delivering or repairing code.

## Verify

Run applicable `ms check`, `ms run` and `ms test` commands after editing. Check behavior, not just compilation; report unrun checks. Include imports. Prelude collections, Optional, Result, Error and print need none. For additional APIs, `ms search_symbol <words>` supplies signatures/imports; do not guess.
