# Comment syntax: `//` and `/* */`

## Summary

- `#` comments are a dense column of marks in long doc blocks and clash with Markdown `#` inside doc text.
- Replace `#` with `//` (line, own line or trailing) and add whole-line, non-nesting `/* ... */` blocks. Hard cut: `#` is an error.
- Decided by Chinmay: `//` plus `/* */`, hard cut, no `"""` or backtick comments, stacked `//` runs of three or more lines become blocks.

## Status

Implemented, 2026-11-03. Direction: "spike on the most cosmetic way of writing comments, current approach of # is turning into bit of an eye sore"; "hard cut, i like //"; "multi line comments are not very readable with //"; "i want the code to look good even without editor help".

## Problem

- Stdlib has about 4,500 comment lines in 98 files; 1,700 hold backticked code, 700 pass 110 columns, 10 trail code, none are blocks.
- A per-line marker is the noise; the glyph matters less. `#` also appears in strings (`"#"`, `&#10;`), which makes searching noisy.

## Design

- `//` runs to the end of the line, alone or after code. `a // b` was already a parse error, so no valid program changes meaning.
- `/* ... */`: starts its own line (after indentation), ends at the first `*/`, and only blanks or a `//` comment may follow. Rejected: nesting (`block comments do not nest`), no closing (`unterminated block comment`, at the opening `/*`), code after `*/`, and a `/*` after code on a line (`a block comment must start its own line; write a trailing comment with '//'`). Contents are free-form and count as comment-only lines for layout.
- `#` is rejected: `unexpected source character '#'; comments start with '//' (or '/* */' for a block)`.
- Doc comments: the `//` lines or `/* */` block directly above a declaration (a blank line detaches), else a trailing `//` on the declaration's line (enum cases, one-line members). Block text drops the markers and the interior's common indentation. One implementation, `ms_syntax::doc`, serves `ms search_symbol`, the generated reference, and LSP hover.
- Formatter: a block is masked like a multi-line text literal, so its contents are never reflowed; the block moves with its indentation and trailing spaces are not touched.
- Rejected markers: `--` (`a --1` is valid), `;` (silently turns `a = 1; b = 2` into a comment, defeating the semicolon diagnostic), `'` (reads as an unclosed text, drops the double-quote hint), `"""` (is a text literal), triple backticks (Markdown fences in docs), `~`.
- Style (stdlib migration): short facts on enum cases and one-line members trail as `//`; prose of three or more lines uses an unstarred `/* */` block; comments that restate a name or signature are deleted.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `ms-syntax` lexer, formatter, partial parser, `doc` | `//`, `/* */`, diagnostics, doc extraction | `tests/comments.rs`, `doc::tests`, format corpus |
| `ms-tooling`, `ms-lsp`, `ms-check` | doc extraction, editor tokens, import trivia | `ms-lsp` and `ms-tooling` tests |
| `.ms`, `.src`, Markdown fences, Rust inline sources | `#` to `//` with a lexer-aware rewrite | `make verify-full` |
| VS Code grammar and language configuration, website highlighter | `//` line and `/* */` block scopes | `tests/docs/highlighting.test.cjs` |
| `grammar.md`, `syntax.md`, `tour.md`, cheat sheet, wiki | rules and examples | `make docs-check` |

## Alternatives considered

- Keep `#` and shorten comments: the marker count per line stays.
- `//` only, no blocks: long prose repeats the marker on every line (rejected by Chinmay).
- A starred block (` * ` per line): reintroduces the per-line column; allowed, not required.
- Doc-only `///`: needs classifying 4,500 existing comments by hand; can be added later without breaking `//`.

## Testing

`cargo test -p ms-syntax` (lexer, formatter, doc), workspace tests, `make conform`, `make e2e`, `make repo-check`, and the highlighter test. Platform-neutral syntax; no gating.
