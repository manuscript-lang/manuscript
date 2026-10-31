# Optional ergonomics: no `some`, default `none`, `?.`

## Summary

- `T?` replaced `Optional[T]` (#1987). This removes the remaining ceremony around optionals.
- Four stages, each its own PR: drop qualified `.none`/`.some`; `T?` defaults to `none`; drop `some`; add `a?.b`.
- Cost: a language-visible migration of about 735 files that mention `some(`; `ms migrate` or a script rewrites them.
- Decision requested: none; this implements Chinmay's direction. Open questions below need a call before stage 3.

## Status

- Proposal, 2026-10-30, checked against main `934c2e24`.
- Direction (Chinmay): "just have none as one value, and keep type to the left"; "`?` should be a lot simpler, they should default to none, and passing a value should not require some ceremony"; "get rid of some altogether"; also patterns, "it's just noise"; "support chaining optional like js, `a.b?.c`".

## Problem

- Writing absence or presence repeats information the type already carries:

```ms
fn find(name: String, limit: Int? = none) Int?:
    return some(3)
```

- `= none` repeats what `T?` already says; `some(3)` is already redundant where an `Int?` is expected (lint MSL113 reports it).
- Reading a field through an optional needs a `match` or `if let` per level.
- Non-goals: changing `Result`, `try`, or `if let` unwrapping.

## Design

Stage 1: no qualified cases.

- `none` is one value whose type comes from the expected type or the binding's annotation.
- `Optional[Int].none`, `Optional[Int].some(x)` and `Int?.none` are rejected: "write the type on the binding, e.g. `let x: Int? = none`".

Stage 2: default `none`.

- A parameter or record field of type `T?` with no default behaves as if written `= none`.
- Callers omit it; declared defaults still win. Positional filling keeps declaration order.

```ms
fn find(name: String, limit: Int?) Int?: ...
find("a")             # limit is none
find("a", 3)          # a plain value wraps implicitly
```

Stage 3: no `some`.

- A plain `T` wraps implicitly wherever `T?` is expected (already true); `some(x)` is rejected with a pointer to the plain value.
- Where no `T?` is expected, annotate: `let x: Int? = 1`.
- Patterns: `if let v = opt:` is unchanged; in `match opt:` the present arm is a bare binding next to `none:` (open question 1).
- `Optional` keeps `some` and `none` internally as its two cases; `some` is no longer a name in the prelude.

Stage 4: `a?.b`.

- `a?.b` is `none` when `a` is `none`, otherwise `a.b`; the type is `B?`, flattened when `B` is already optional (open question 2).
- `a?.f(args)` evaluates `args` only when `a` is present; a chain `a?.b?.c` short-circuits at the first `none`.
- `?.` lexes as `?` then `.` with no space; `a ?.b` is rejected.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `crates/ms-syntax` | `?.` postfix; match-arm binding; reject `some(` | parse, parse-error corpus |
| `crates/ms-check` | default `none` for `T?`; reject qualified and `some`; chaining typing | conformance accept and reject |
| `crates/ms-lower`, `ms-clif` | lower `?.` as a presence test and branch; no `some` case lookup | e2e fixtures |
| `stdlib/*.ms`, `bindings.json` | drop `= none` and `some(` | stdlib fixtures |
| `crates/ms-tooling` | retire MSL113; formatter; LSP completion | lint and snapshot tests |
| docs, guide, VS Code grammar | rewrite optional chapter, add `?.` | docs-check |

## Alternatives

- Do nothing: keeps `= none` and `some(...)` noise, which the user rejected.
- Keep `some` as an optional spelling: two ways to write the same thing; MSL113 already flags it.
- `?` only for types, no chaining: leaves the per-level `match` cost.

## Staging and verification

- Each stage lands green on `make verify`, conformance and e2e, with migrations done by script and expectations re-recorded.
- Stage 3 is the largest; it needs a migration script that rewrites `some(x)` to `x` (or an annotation) and match arms, checked by `ms check` on every migrated file.

## Open questions

1. Present arm in `match`: bare binding (`v:`), or only `if let`? Recommendation: bare binding, since `match` stays exhaustive.
2. `a?.b` where `b` is `C?`: flatten to `C?` (recommended, JS-like) or nest to `C??`?
