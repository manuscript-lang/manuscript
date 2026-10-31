# Make the surface distinctly Manuscript

## Summary

- Problem: the Python-aligned surface (`def`, `lambda`, `elif`, `True`, `f""`, `from "p" import`, `Callable[[..]]`, `case` arms) makes agents write Python. The Haiku rerun logged 20 capitalized `True`/`False` errors, plus `def`/`lambda`/`elif` habits where the semantics differ.
- Change: spell a construct like Python only when it behaves like Python. Eleven spellings change; grammar structure, layout rules and semantics do not.
- Cost: a one-off token converter (not committed) rewrote the corpus; the parser gains one `fn` form and a table of targeted foreign-word diagnostics.
- Decision requested: none outstanding. Approved by Chinmay as written below.

## Status

Implemented on `claude/project-thread-1z7efx`, 2026-10-28. Direction (Chinmay): "i think bot is trying to much to write python, we need to have slightly different syntax to ensure it understand its manuscript, like lower case true false and fn instead of def"; "yeah this looks good, i like lambda which takes fewer tokens, can we do something to simplify that" (answered by bare closures `fn x: x + 1`); "let's do fn form". `with` is out of scope: it is removed by its own thread ("no with please").

## Problem

- The earlier agent bench (Haiku, 20 challenges) passed 15/20 on v1 spelling, 14/20 on v1 plus diagnostics and 15/20 on the Python-aligned surface: Python spelling bought no measurable pass rate.
- It costs recognition: near-Python code carries no signal that aliasing, truthiness (`if` needs a `Bool`) and error handling (no exceptions) differ.
- Non-goals: new semantics, new keywords beyond `fn`/`unit`/`true`/`false`, a dual grammar.

## Design

| # | before | after |
| --- | --- | --- |
| 1 | `def f(a: Int) -> Int:` | `fn f(a: Int) Int:` |
| 2 | `lambda v: v + 1`, `lambda (v: Int) -> Int:` | `fn v: v + 1`, `fn a, b: a + b`, `fn: 1`, `fn(v: Int) Int: ...` |
| 3 | `Callable[[Int], Int]` | `fn(Int) Int` (types only; parameter names are not identity) |
| 4 | `True` / `False` | `true` / `false` |
| 5 | `()` as the Unit value | `unit` |
| 6 | `elif c:` | `else if c:` |
| 7 | `a if c else b` | `if c: a else: b` (chains with `else if`) |
| 8 | `f"hi {name}"` | `"hi {name}"` (every string interpolates; literal braces are `\{` `\}`) |
| 9 | `from "p" import A, B` | `import A, B from "p"` (`import A from "p"` for one name) |
| 10 | `case P(a):` / `case _:` arms | `P(a):` / `_:` (alternatives in `type` keep `case`) |
| 11 | `extern def` | `extern fn` |

- An inline closure body that starts with `if` is parenthesized: `fn x: (if x > 0: 1 else: 0)`.
- Every Python word gets a targeted parse or resolution diagnostic with the remedy: `def`, `lambda`, `elif`, `True`/`False`/`None`, `Callable[...]`, `f"..."`, `from ... import`, `case` arms, `()`, `->`, `a if c else b`. Recorded as `tests/conformance/fixtures/snippets/foreign-*` and `diag-spelling-capital-true`.
- Displayed types (hover, diagnostics, API pages) use the same spelling through `ms-check/src/types.rs`.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `ms-syntax` token, lexer, parser, formatter | tokens `fn`/`unit`/`true`/`false`; one `fn` form; `import .. from`; arms without `case`; interpolating strings; foreign-word diagnostics | `tests/corpus.rs`, `nested_text.rs`, `lambda_hints.rs`, conformance |
| `ms-check` | type display, hints, import fixes, `import` suggestions | `golden.rs`, `callable_identity.rs`, conformance |
| `ms-lsp`, `extensions/vscode` | completion, snippets, import actions, interpolation context, TextMate grammar | `ms-lsp` snapshots, `extensions/vscode/tests`, `tests/docs/highlighting.test.cjs` |
| `ms-tooling` | `ms guide`, API pages, mistakes list | `guide_pages.rs`, `docs-check` |
| stdlib, tests, examples, bench, docs | converted by script, then `ms fmt` | `make verify`, `make conform`, `make e2e` |
| `ms-mir`, `ms-clif`, `ms-lower` | unchanged (their text format is not source syntax) | n/a |

## Alternatives

- Keep Python spelling and add diagnostics: they fire only after an agent has already written Python, and the guide had not stopped it (first build ok 45%).
- Keep `->` before result types: it is the Python tell the change removes; the diagnostic makes the remedy one step.
- Keep `lambda` as an alias: two closure spellings double the surface agents can mix up.

## Verification

- `make verify`, `make conform` (2393/2393) and the e2e corpus pass.
- Haiku agent-bench rerun on the 20 challenges against `bench/agent/results/summary-2026-10-28-guide.md` (18/20, 45% first build, 22.1 turns); results page added under `bench/agent/results/`.
