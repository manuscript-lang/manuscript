[Wiki](../index.md) › [Tooling and docs](index.md)

# Agents get machine-applicable fixes, structured faults and named replacements

Decision: diagnostics carry a `fix` field when the repair is mechanical (nearest-name misspellings, missing imports), and `ms check --fix` / `ms lint --fix` apply them in place and report what remains (no `--watch`). `ms run --json` and `ms test --json` report a runtime fault as data (versioned result with the fault location) instead of text on stderr.

Apply when: adding or rewording diagnostics, or changing JSON output.
Evidence: [CLI help](../../crates/ms-cli/src/help_text.rs), [diagnostics](../../documentation/developer-tooling/source/diagnostics.md), [fault report](../../crates/ms-cli/src/fault.rs).
Verify: a misspelled name is fixed by `ms check --fix`; `ms run --json` on a faulting program exits with a JSON fault; each new hint has a test and a re-recorded golden.

Lesson (fix safety): sweep `--fix` over the fixture corpus (fix, then re-check; new parse or resolution errors are bugs). It found fixes that produced invalid source: a candidate list offering a name with no writable spelling (`Optional`), a conversion applied to a compound-assignment target (the parser clones the target as the left operand), a `.clone()` inserted after a whole closure, and an edit set that together emptied an import group. A fix is single-edit and local: when the repair needs a rename or two edits, carry no fix.

Decision (no clone fixes): ownership errors carry prose, never a `.clone()` fix. A Haiku run over the 20 ms challenges ([results](../../bench/agent/results/summary-2026-11-09-guide.md)) showed agents take the clone as a cheap way out: clones per 1000 source lines rose from 30.5 to 39.9 after the message only suggested restructuring first. The owner (2026-11-09) asked to stop treating clone as the fix. Test: `ownership_errors_never_carry_a_clone_fix`.

Import repairs must retain declaration kind (#3288). A function or constant with the requested name cannot repair an unknown type; an exported `fn Bytes` previously replaced the valid standard `Bytes` import. Filter standard symbols and project export headers by type kind before selecting compiler fixes or editor actions. Keep value-reference imports available, and apply each offered repair then recheck the resulting source (`ms-driver` import-hint and `ms-lsp` editing regression tests).
