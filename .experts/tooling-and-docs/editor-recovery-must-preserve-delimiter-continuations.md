[Wiki](../index.md) › [Tooling and docs](index.md)

# Editor recovery must preserve delimiter continuations

Verified: strict parsing accepts multiline parameters, but declaration recovery that splits their column-zero closing delimiters into separate chunks whenever any declaration is malformed discards valid functions and their parameter scopes in the language server. Recovery must consult the lexer for continuation boundaries while fresh declarations still synchronize after an unmatched opener. Completion snapshots also need a match arm, rather than an ordinary statement, to repair an unfinished `match` suite.

Apply when: changing partial parsing, declaration synchronization, or completion snapshot repair.
Evidence: [layout rules](../../documentation/core-language/basics/grammar.md#layout-tokens); [partial parsing](../../crates/ms-syntax/src/partial.rs); [completion](../../crates/ms-lsp/src/completion.rs); [partial parse corpus](../../crates/ms-syntax/tests/data/partial).
Verify: multiline function parameters retain their original LF/CRLF positions, navigation, and completion when a different declaration is incomplete; an unfinished match does not erase completion in the enclosing function.

Verified: a completion marker can change argument binding or join an operand at a cursor boundary. Signature help selects the argument from the original source, including explicit labels and positional slots, before querying a repaired snapshot. Lambda parameter commas and nested delimiters belong to their expressions. Evidence: [signature help](../../crates/ms-lsp/src/completion.rs), [boundary regressions](../../crates/ms-lsp/tests/signature_help.rs). Verify operand/comma/closing boundaries, reordered labels, bare identifiers matching other parameter names, and unfinished LF/CRLF calls; the private query must preserve the live document.

---
Topics: [Diagnostics and tooling](../topics/diagnostics-and-tooling.md)
