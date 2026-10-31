[Wiki](../index.md) › [Tooling and docs](index.md)

# Agents get machine-applicable fixes, structured faults and named replacements

Decision: diagnostics carry a `fix` field when the repair is mechanical (nearest-name misspellings, missing imports), and `ms check --fix` / `ms lint --fix` apply them in place and report what remains (no `--watch`). `ms run --json` and `ms test --json` report a runtime fault as data (versioned result with the fault location) instead of text on stderr.

Apply when: adding or rewording diagnostics, or changing JSON output.
Evidence: [CLI help](../../crates/ms-cli/src/help_text.rs), [diagnostics](../../documentation/developer-tooling/source/diagnostics.md), [fault report](../../crates/ms-cli/src/fault.rs).
Verify: a misspelled name is fixed by `ms check --fix`; `ms run --json` on a faulting program exits with a JSON fault; each new hint has a test and a re-recorded golden.
