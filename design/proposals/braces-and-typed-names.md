# Braces for blocks and colon-free typed names

## Summary
- Problem: `:` means five things today (type, block start, label, arm, map entry), and indentation decides block ends.
- Change: a name is followed by its type; `{ }` for every block; `=>` for one expression; labels stay; `:` only for labels, map entries and destructuring renames.
- Decision requested: approve the rules, then a stage plan for the compiler, formatter and migration.

## Status
Implemented 2026-11-24 in four stacked changes (colon-free types, arrows, braces, grouped names). Decisions from Chinmay in the thread: braces on every block, arrows for arms and closures, labels kept (decided 2026-11-24 after the skip-default discussion). Measured on five samples: +18% lines, +4% characters. Examples are hand-written (`examples-final.md`) and cannot pass `ms check` until the parser changes.

## Problem
- Colon overload: `fn f(a: Int)` (type), `if x:` (block), `f(a: 1)` (label), `Circle(r): ...` (arm), `{k: v}` (map).
- Layout is significant: `src/compiler/syntax/lex_layout.c` turns indentation into block tokens.
- Verified scale: 6570 `.ms` files and 76 documentation pages with ```manuscript fences use the current syntax.

## Design
Rules:
- Typed name: `name Type`, optionally `= value`. Applies to fields, params, enum payloads, `var` locals, generic limits (`[T Comparable]`).
- `{ }` holds statements for every block: `fn`, `if`, `else`, `for`, `while`, `match`, `type`, `enum`, `interface`, even on one line. `} else {` stays on one line. A bare `{ }` at statement start is a scope: its locals and resources end at `}`.
- `=>` introduces one expression: match arms (`Param(name) => name.clone()`), closures (`s => f(s)`, `(a, b) => a + b`, `() => 1`, `s => { ... }`) and one-expression functions (`fn f(x Int) Int => x + 1`). `return` is allowed as an arm expression, as today.
- Typed closures keep `fn`: `fn(v Int) Int { return v - 1 }`.
- Argument labels stay unchanged (`read_file(path, max_bytes: n)`, `Options(limit: 2)`); required parameters still come before defaulted ones. No `Name{ }` construction form and no `_` skipping.
- Verified scale of labels today: about 11,000 label-like spots in 3,630 `.ms` files under `src/stdlib` and `tests` (upper bound, includes some map entries).

Ambiguities and resolutions:
- Block `{` vs map literal: a map literal is an expression holding `key: value`; `{` after a header, `=>`, `else` or at statement start is a block. Needs parser tests, including empty `{}`.
- `name Type` vs two expressions: a statement starting `ident ident` is a declaration; expressions never juxtapose names.
- Typed `:=` (`ok fn(Int) Int := f`) is removed; write `var ok fn(Int) Int = f`.
- `(a, b) =>` vs a parenthesized expression: one token of lookahead past the matching `)`.
- Result type before `{`: `fn f() Map[K, V] {` is fine; types never contain a bare `{`.
- Destructuring: a statement-start `{` whose matching `}` is followed by `:=` is a pattern; otherwise a scope. `=> {` is always a block; a map literal there needs parentheses. A typed immutable binding stays `x Int := v`.
- Newlines still end statements; indentation stops carrying meaning and the formatter owns it.

## Components touched
| Component | Change | Test |
| --- | --- | --- |
| `src/compiler/syntax/lex_layout.c` | drop indentation blocks, add brace tokens | lexer unit tests |
| `src/compiler/syntax/parse*.c` | typed names, bodies, arrows | parser fixtures, reject cases |
| `src/compiler/syntax/format*.c` | print braces and arrows | formatter idempotence |
| migration tool (old to new, once) | rewrite every `.ms` and Markdown fence; `name: Type` becomes `name Type` | `ms check` on all 6570 files |
| `src/stdlib/**`, `tests/conformance`, `examples`, `bench` | migrated by the tool | `make verify-full` |
| `documentation/`, `extensions/agent-skill`, `VISION.md` | new examples | `docs-check` |
| `src/lsp`, editor grammars | tokens, folding | LSP tests |

## Alternatives
- Do nothing: keeps five meanings for `:` and no explicit block ends; each is a paper cut, none is a bug.
- Braces on functions only: mixes two block styles in one function.
- Colon for one-line bodies and arms: overloads `:` again; Chinmay found it awkward.
- Keep `name: Type`: then `{ }` plus `:` stays overloaded; this is the part Chinmay asked to drop.

## Stages
Three changes, each green on `main`:
1. Colon-free types (`name Type`, `x Int := v`), migration tool, formatter.
2. `=>` for arms, closures and one-expression functions.
3. Braces for every block, lexer rework, `test`/`bench`/`fixture`/`...` bodies, bare scopes.

## Open questions
- Keep `fn` for untyped closures too (`fn s => ...`)? Recommend no; `=>` alone is enough.
- Breaking change for every user and agent skill; recommend no compatibility period beyond stage 1 (release version is 2026.11.0, language still changing).
