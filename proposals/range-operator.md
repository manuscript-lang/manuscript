# Range operator `a..b`

## Summary

- `for i in range(0, n)` needs an import line and a call; `for i in 0..n` is shorter and removes the import.
- Add `a..b` as an exclusive Int range expression that means exactly `range(a, b)` from `@std/collections.ms`.
- No new type, keyword, step syntax, or runtime entry point; the existing counter-loop lowering applies unchanged.
- Decision requested: approve exclusive `..`, expression-wide use, and no step or inclusive form.

## Status

Proposal, 2026-10-24, checked against `main`. Direction: "lets add support for 0..n for loops in manuscript, range uses more tokens".

## Problem

- Counting needs `from "@std/collections.ms" import range` plus `range(0, n)`. Verified: without the import, `ms check` reports `unknown binding range; add: from "@std/collections.ms" import range`.
- `0..5` is rejected today: `parse: Manuscript has no '..' range; to count, \`for i in range(0, 10):\` ...` (`crates/ms-syntax/src/parser.rs`).
- `documentation/core-language/control-flow/loops.md` states "no range syntax" and that `for index in 0..5:` is unsupported.
- Non-goals: steps, descending ranges, inclusive ranges, lazy range values, iteration protocols.

## Design

- Grammar: `start..end`, both `Int` expressions. Exclusive of `end`, like `range`. `end <= start` is empty. Bounds evaluate once, in order.
- Precedence: below `+ -`, above comparisons. `0..n + 1` is `0..(n + 1)`. Non-associative: `a..b..c` is a parse error.
- Meaning: identical to `range(a, b)`, typed `List[Int]`. Valid anywhere an expression is, not only in `for`; as a plain value it is the same list, with the same 268,435,456-item fault.
- Counter loop: the checker resolves `..` to the `collections.range` symbol, so `range_bounds` in `crates/ms-lower/src/stmt.rs` sees the same call and emits an allocation-free loop. No lowering special case.
- Steps: none. `range_by(start:, end:, step:, max_items:)` stays the stepped, descending, and bounded form.
- `range` stays: it is the general function, needed for the first-class and named-argument uses. Its diagnostics are unchanged.
- Diagnostics: the `no '..' range` parse error is removed. `a..b..c` and non-Int bounds get checker/parse errors that name `range_by` for steps.
- Cross-platform: syntax only; no platform-specific code or test gating.

Intended examples (checked after implementation):

```manuscript
from "@std/io.ms" import stdout

def main() -> Unit:
    var total = 0
    for i in 0..5:
        total += i
    stdout().write("{total}\n")
```

Verified today on `main`: `for i in 0..5:` fails with the `no '..' range` parse error above; the `range(0, 5)` form passes `ms check` once `print` is replaced by `stdout().write`.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `crates/ms-syntax` lexer/parser | `..` token, binary level, new AST node, remove old error | parser reject/accept cases |
| `crates/ms-syntax/src/format.rs` | print `a..b` without spaces | formatter idempotence case |
| `crates/ms-check` | resolve `..` to `collections.range`, Int bounds | conformance accept and reject |
| `crates/ms-lower` | unchanged (range call recognized as today) | e2e counter-loop and value fixtures |
| `crates/ms-mir`, `ms-clif`, `ms-rt` | unchanged | none |
| `stdlib/collections.ms` | doc comment on `range` mentions `a..b` | `make docs` freshness |
| `crates/ms-lsp`, VS Code grammar | tokenize/hover `..` | LSP token test |
| `documentation/core-language/control-flow/loops.md`, `ms guide` (`crates/ms-tooling/data/cheatsheet.md`) | teach `0..n`, drop "unsupported" | book/example checks |

## Alternatives

- Do nothing: costs an import and a call on every counted loop, the most common loop in agent-written code.
- `for`-only syntax (`for i in 0..n`): needs loop-specific parser and lowering; rejected for special-casing.
- Inclusive `..=` or both: two forms where one suffices; `0..n + 1` covers it.
- `n.times()`-style stdlib method: no import saved and a different shape from `range`.
- Step syntax `0..n..2`: `range_by` already covers it with checked failure modes.

## Staging and verification

1. Parser, formatter, checker, tests, docs in one PR (one rule across surfaces). Gate: `make verify`, conformance accept/reject, an e2e fixture on all three OSes.
2. Remove `no '..' range` text from docs and diagnostics in the same PR.

## Open questions

- Should `a..b` be allowed outside `for`? Recommend yes (same value as `range`; a `for`-only rule needs special-casing).
- Keep non-associative with no step form? Recommend yes.
