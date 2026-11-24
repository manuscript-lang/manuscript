[Wiki](../index.md) › [Language](index.md)

# Every block is braced and arrows hold one expression

Decision (Chinmay, 2026-11-24): `{ }` opens every block, even one line; indentation carries no meaning and `ms fmt` computes it (tabs on disk). A bare `{ }` statement is a scope. `=>` introduces exactly one expression (match arms, `s => f(s)`, `(a, b) => a + b`, `() => 1`, `fn f() Int => 1`); `=> {` is always a block, so a map there needs parentheses. Typed closures keep `fn(v Int) Int { ... }`. `if c { } else { }` keeps `} else {` on one line. Labels stay.

Apply when: changing the lexer, block or arm parsing, the formatter, recovery, diagnostics that print code, or any example.
Evidence: [proposal](../../proposals/braces-and-typed-names.md), [grammar](../../../documentation/core-language/basics/grammar.md), [removed spellings](../../../documentation/core-language/removed-spellings.md), `lex_token.c` (`brace_is_map`, `brace_destructures`), `format_blocks.c`.
Verify: the lexer tells a block `{` from a map or destructuring `{` by the token before it and by `:=`/`=` after the matching `}`; `Newline` is not emitted after a block close; a doc comment must follow the closing `}` of the previous declaration, not sit inside it; diagnostic text printing code uses brace forms (an LSP or conformance fixture records them).
