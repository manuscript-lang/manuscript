# Indent with tabs

## Summary

- Problem: four-space indentation is a separate token on every first-level line, so it costs about 3% of source tokens against a tab, which merges into the next keyword.
- Change: the lexer accepts one tab per indent level in code, and `ms fmt` writes tabs. Four spaces per level stays accepted; `ms fmt` rewrites it.
- Decision requested: none; Chinmay asked for it. Sequencing against the `let` to `:=` rewrite, which also touches every `.ms` file, is the one open question.

## Status

Stage 1 implemented, 2026-11-10; skeptical review: revise (virtual column, missed helper sites), both folded in. Stage 2 proposed, checked against `5752aefd`. Direction (Chinmay): "i don't thin tab saves that much, can you check" then, after the measurement below, "do the tab fmt".

## Problem

Measured (leading groups of four spaces replaced by one tab; independently re-measured by the review subagent): the 10 `bench/agent/challenges/*/solutions/ms/*.ref` programs, and `stdlib/*.ms` (2.1% with comments, 3.2% on code lines):

| Tokenizer | Spaces | Tabs | Saved |
| --- | --- | --- | --- |
| o200k_base | 8746 | 8481 | 3.0% |
| cl100k_base | 8734 | 8465 | 3.1% |

- `if` at depth 1 tokenizes as `   ` + ` if` with spaces and `\tif` with a tab. Depth 2 and deeper cost the same, so the saving is one token per depth-1 line.
- Claude's own tokenizer is not measured; both public ones agree. Cost: one lexer rule, one formatter pass, and a repository-wide reformat.

## Design

- Lexer (`crates/ms-syntax/src/lexer.rs`): a tab in a line's leading whitespace counts as one level (4 columns). Spaces after tabs align continuation lines as spaces do today. A tab anywhere else in code stays an error; tabs remain legal inside text and comments.
- Mixed leading whitespace is allowed only as tabs then spaces. Spaces then a tab is `a tab cannot follow spaces in indentation`.
- Offsets stay exact byte offsets. `Pos.column` is the display column: a leading tab advances it by 4, so `column + len`, `column - 1` indent text and the parser's `indent + 4` binding-group checks hold unchanged. Sites that used a column as a byte index (`format.rs`) only ever see space-expanded text.
- Multi-line text dedent counts a tab as four columns (`parser.rs` text dedent); the formatter's text shifting strips columns, not bytes (`format.rs` `strip_columns`).
- `ms fmt` keeps its space model: leading tabs on code lines expand to four spaces on entry (lines inside multi-line text and block comments are untouched). Stage 2 converts leading groups of four spaces to tabs on exit and counts a tab as four toward the 88-column width.
- `ms init` template, guide, docs and examples switch to tabs; the "four spaces per level" rule becomes "one tab per level".

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `crates/ms-syntax/src/lexer.rs`, `parser.rs` | accept leading tabs, new diagnostics, text dedent | `format_edits`, parse-errors corpus |
| `crates/ms-syntax/src/format.rs` | entry and exit conversion, width | `format_edits`, corpus goldens |
| `crates/ms-lsp/src/editor.rs`, `features.rs`; `ms-repo-check/src/nested.rs`; `ms-check/src/suggestions.rs` | indent helpers that trim only `' '` or emit four spaces (stage 2) | LSP code-action and folding tests |
| `documentation/`, `ms guide`, `ms init` | tab wording | `guide_pages`, init test |
| `tests/conformance` | `-fmt` twins re-recorded | `make conform` |

## Alternatives

- Do nothing: 3% of tokens stay on whitespace.
- Two-space indent: measured 0% saved; whitespace runs tokenize as one token at any width.
- Tabs only, reject spaces: breaks every unformatted file and agent output; accepting both costs one lexer branch and `ms fmt` converges them.

## Stages

1. Lexer and parser accept tabs, `ms fmt` reads them and still writes spaces. Check: new cases, golden and conformance parse re-recorded for the accepted tab inputs.
2. `ms fmt` writes tabs, repository reformatted, twins re-recorded, helper sites above fixed. Check: `make verify-full`. Lands after the `:=` migration.

## Open questions

- Land before or after the `let` to `:=` migration? Both rewrite every `.ms` file, so every open branch touching `.ms` conflicts once. Recommend tabs after `:=`, so the repository is rewritten for tabs once, in a single mechanical `ms fmt` run on `main`.
