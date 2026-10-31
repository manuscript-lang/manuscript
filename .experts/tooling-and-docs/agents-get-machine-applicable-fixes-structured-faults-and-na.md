[Wiki](../index.md) › [Tooling and docs](index.md)

# Agents get machine-applicable fixes, structured faults and named replacements

Decision: diagnostics carry a `fix` field when the repair is mechanical (nearest-name misspellings, missing imports), and `ms check --fix` / `ms lint --fix` apply them in place and report what remains (no `--watch`). `ms run --json` and `ms test --json` report a runtime fault as data (versioned result with the fault location) instead of text on stderr. Habits from TypeScript, Go and Rust get a named replacement in the diagnostic (`unwrap`/`expect`/`unwrap_or` point to `get(default)`, `if let` or `try`; `len`, `Some`, `Ok`, `parseInt`, `for (...)`, `Int("1")`; any camelCase member maps to snake_case; mixing Int and Float says `to_float()` or `truncate_to_int()`). Known gap: `for (let i = 0; ...; i++)` reports the `;` error first because the lexer fires before the parser.

Apply when: adding or rewording diagnostics, or changing JSON output.
Evidence: [CLI help](../../crates/ms-cli/src/help_text.rs), [diagnostics](../../documentation/developer-tooling/source/diagnostics.md), [fault report](../../crates/ms-cli/src/fault.rs).
Verify: a misspelled name is fixed by `ms check --fix`; `ms run --json` on a faulting program exits with a JSON fault; each new hint has a test and a re-recorded golden.

---
Topics: [Errors and results](../topics/errors-and-results.md) · [Diagnostics and tooling](../topics/diagnostics-and-tooling.md)
