[Wiki](../index.md) › [Tooling and docs](index.md)

# Editor recovery must preserve delimiter continuations

Verified: strict parsing accepts multiline parameters, but declaration recovery that splits their column-zero closing delimiters into separate chunks whenever any declaration is malformed discards valid functions and their parameter scopes in the language server. Recovery must consult the lexer for continuation boundaries while fresh declarations still synchronize after an unmatched opener. Completion snapshots also need a match arm, rather than an ordinary statement, to repair an unfinished `match` suite.

Verified: recovery synchronization and optimistic parse bounds must recognize the same declaration starts at token boundaries, including `import(`, `test"name"`, contextual `bench "name"`, and `opaque type`. Otherwise an unfinished opener swallows valid following declarations. Contextual names alone remain parameter continuations.

Apply when: changing partial parsing, declaration synchronization, or completion snapshot repair.
Evidence: [layout rules](../../documentation/core-language/basics/grammar.md#layout-tokens); [partial parsing](../../crates/ms-syntax/src/partial.rs); [completion](../../crates/ms-lsp/src/completion.rs); [partial parse corpus](../../crates/ms-syntax/tests/data/partial); [declaration recovery regressions](../../crates/ms-syntax/tests/recovery_declarations.rs).
Verify: multiline function parameters retain their original LF/CRLF positions, navigation, and completion when a different declaration is incomplete; an unfinished match does not erase completion in the enclosing function.
