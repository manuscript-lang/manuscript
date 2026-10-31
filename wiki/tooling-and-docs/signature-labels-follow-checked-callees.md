[Wiki](../index.md) › [Tooling and docs](index.md)

# Signature labels follow checked callees

Verified: scanning backward to a statement separator makes signature help label `1 + combine(...)` as `1 + combine`. Read the callee's checked span from the same repaired snapshot instead. Grouping parentheses excluded from syntax spans can still close inside a receiver, so retain their openers; scan interpolation expressions separately from their surrounding string.

Apply when: changing signature help, callee text, or repaired editor snapshots.
Evidence: [signature labels](../../crates/ms-lsp/src/completion.rs); [boundary and server-edit regressions](../../crates/ms-lsp/tests/signature_help.rs).
Verify: operator prefixes stay out of labels, `(pair).combine` remains balanced inside interpolation, and LF/CRLF server edits use the current snapshot.
