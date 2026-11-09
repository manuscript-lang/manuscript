[Wiki](../index.md) › [Tooling and docs](index.md)

# Agents get machine-applicable fixes, structured faults and named replacements

Decision: diagnostics carry a `fix` field when the repair is mechanical (nearest-name misspellings, missing imports), and `ms check --fix` / `ms lint --fix` apply them in place and report what remains (no `--watch`). `ms run --json` and `ms test --json` report a runtime fault as data (versioned result with the fault location) instead of text on stderr.

Apply when: adding or rewording diagnostics, or changing JSON output.
Evidence: [CLI help](../../crates/ms-cli/src/help_text.rs), [diagnostics](../../documentation/developer-tooling/source/diagnostics.md), [fault report](../../crates/ms-cli/src/fault.rs).

Lesson (collection paths, [#3301](https://github.com/manuscript-lang/manuscript/issues/3301)): moving a diagnostic from a source root to invocation-relative paths must also move its embedded fix boundaries. Test separate roots with identical basenames by applying the emitted edits and rechecking; comparing the surrounding diagnostic alone misses an edit aimed at another file.

Verify: a misspelled name is fixed by `ms check --fix`; `ms run --json` on a faulting program exits with a JSON fault; each new hint has a test and a re-recorded golden.

Lesson (fix safety): sweep `--fix` over the fixture corpus (fix, then re-check; new parse or resolution errors are bugs). It found fixes that produced invalid source: a candidate list offering a name with no writable spelling (`Optional`), a conversion applied to a compound-assignment target (the parser clones the target as the left operand), a `.clone()` inserted after a whole closure, and an edit set that together emptied an import group. A fix is single-edit and local: when the repair needs a rename or two edits, carry no fix.
