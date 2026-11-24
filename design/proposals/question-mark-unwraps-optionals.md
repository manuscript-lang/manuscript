# `?` unwraps Optionals and Results; `?.` is retired

## Summary

- Problem: `f()?.name` on a Result is rejected because `?.` is a separate Optional-only operator. Agents write it (6 of 63 first-build runs, `agent-bench` f37b8c6) and `?` versus `?.` is a standing source of confusion (#4520).
- Change: postfix `?` means "the value, or leave the function" for both types. On a `T?` operand, `none` returns `none`; `a?.b` is no longer a token, it is `(a?).b`.
- Decision requested: none; approved by Chinmay, 2026-11-18 ("okay let's do it"), reversing the 2026-11-14 note that `?.` stays Optional-only.

## Status

Implemented, 2026-11-18, on `a109eb59`. Direction (Chinmay): "yeah why can't we use the access level self has? ? should not give any permissions in it own, it should get it from the variable it being applied on"; absent in a `Void` function returns, lexically ("it should follow the lexical scoped for returning"). Skeptic subagent review skipped: the user chose this design after seeing the trade-offs.

## Problem

```manuscript
masked := compile("[0-9]+")?.replace_all("took 340ms", "N", none)?
```

Rejected today: `?.` needs an Optional receiver. `?.` also never exits while `?` does, so two near-identical tokens have opposite control flow. `?.` has 0 uses in `stdlib/`, `examples/` and `documentation/`; it appears in conformance fixtures only.

## Design

- `x?` where `x: T?` has type `T`. If `x` is `none` the nearest enclosing function or closure returns `none` (result `U?`) or just returns (`Void`). The checker rejects any other result type.
- A function cannot mix the two: `?` on a Result needs a Result return, `?` on an Optional an Optional return. Convert explicitly (`if v := x:`, `get_or`).
- `a?.b` parses as `(a?).b`; the chain desugaring (`chain_match`, `Arm::chain`) is deleted. Writing `?.` after a Result now works with no special case.
- Inside a lambda `?` returns from the lambda, as for Results. Lowering a `none` return drops nothing: the operand held no payload.
- `place[key]?` stays the in-place probe in `if var` heads.
- Ownership: the payload moves out of a temporary operand and is borrowed from a place, exactly as the `ok` payload of a Result. No refcount, no implicit copy.
- Access: `x?` adds none of its own; a `var fn` call or change through `x?` on a place changes the optional in place when `x` is `var`, and is rejected like any change to that binding otherwise (`place`/`is_place` in the ownership walker, `mutation::optional_try` and `alias_payload_addr` in lowering).

```manuscript
fn city(p: Person?) String?:
    return p?.address?.city           // same text; now exits with none instead of chaining
```

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `ms-syntax` parser | drop `?.` chain, `Arm::chain` | parser tests, conformance |
| `ms-check` | `check_try` accepts Optional, new diagnostics; chain code removed | reject fixtures |
| `ms-check` ownership | `try_return` ignores Optional operands | `make copy-check` |
| `ms-lower` | `try_expr` lowers Optional | e2e fixture |
| docs, wiki | propagation, optionals, decision page | `make docs` |

## Alternatives

- Do nothing: the diagnostic names the repair, but the confusion stays.
- Make `?.` accept Results: hides an early exit behind an Optional-looking token.
- Drop `?.` and keep `?` Result-only: loses short chains for `if` nesting.
