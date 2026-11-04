[Wiki](../index.md) › [Tooling and docs](index.md)

# Signature labels follow checked callees

Verified: scanning backward to a statement separator makes signature help label `1 + combine(...)` as `1 + combine`. Read the callee's checked span from the same repaired snapshot instead. Grouping parentheses excluded from syntax spans can still close inside a receiver, so retain their openers; scan interpolation expressions separately from their surrounding string.

Verified: mutation now belongs to checked function parameters, including methods and function values; declaration-only lookup drops `var` from their snippets and signatures. Argument labels and lexical values can share a spelling, and an existing label's colon/value must survive its edit. Track parameter/result delimiters across lines while keeping defaults and inline suites in expression context; an unrelated unmatched declaration must not change that context. Reuse the cursor's token/continuation facts to preserve existing calls and generic applications, including those continued after comments.

Apply when: changing signature help, callee text, or repaired editor snapshots.
Evidence: [signature labels](../../crates/ms-lsp/src/completion.rs); [completion edits](../../crates/ms-lsp/tests/completion.rs); [boundary and server-edit regressions](../../crates/ms-lsp/tests/signature_help.rs).
Verify: operator prefixes stay out of labels, `(pair).combine` remains balanced inside interpolation, and LF/CRLF server edits use the current snapshot.
