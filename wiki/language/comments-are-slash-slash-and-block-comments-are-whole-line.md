[Wiki](../index.md) › [Language](index.md)

# Comments are `//` and `/* */`, and blocks are whole-line

Decision (2026-11-03, Chinmay): `#` is gone (hard cut, `#` is an error). `//` is a line comment, own line or trailing. `/* ... */` is a non-nesting block that starts its own line and may be followed only by blanks or a `//` comment. Rejected alternatives and why: `--` (`a --1` is valid and would silently become a comment), `;` (turns `a = 1; b = 2` into a silent comment), `'` (reads as an unclosed text, drops the double-quote hint), `"""` (a text literal), backticks (Markdown fences in doc text), a required ` * ` line prefix (a per-line column of marks is the noise this change removes).

Apply when: touching the lexer, the formatter, doc extraction, or any tool that reads `.ms` text.
- Doc comments are the `//` lines or `/* */` block directly above a declaration, else a trailing `//` on its line. `ms_syntax::doc` is the only extractor; the generated reference, `search_symbol`, and LSP hover share it.
- The formatter masks a block like a multi-line text literal (`//` placeholder), so contents are never reflowed. The formatter writes trailing comments with exactly two spaces before `//`; do not hand-align them.
- Magic headers in fixtures are `// conform:`, `// expect-mir:`, `// expect-stdout:`, `// error:`. Rewriting `#` to `//` shifts byte offsets, so recorded conformance diagnostics need `ms-conform record` and a check that only `offset` and comment text changed.
- A mechanical rewrite must be lexer-aware (text, interpolation, `r"""`); Rust string literals that hold `.ms` and extra extensions (`.src`, `.source`, `.expected`, `.ms.ref`) need their own pass.

Evidence: [proposal](../../proposals/comment-syntax.md), [syntax tests](../../crates/ms-syntax/tests/comments.rs).
Verify: `cargo test -p ms-syntax --test comments`, `make conform`, `make repo-check`.
