# Results borrow by default; `move` on the result marks a new value

## Summary

- Problem: whether a call's result borrows or owns is guessed from the callee's body, a Rust name table and a program-wide fixpoint. Calls through interfaces, function values and natives have no body to read.
- Change: the signature states it. A non-Copy result borrows from the call's borrowed arguments unless the return type says `move`. The body is checked against that, one function at a time.
- Decision requested: approve the rule and the three open questions. Implementation waits for the C port (#5273).

## Status

Proposal, 2026-11-21, checked against `58e5a1a9`. Not implemented. Direction from Chinmay (2026-11-21, project thread): default borrow, `move` on the return type for a new value, no marker for borrows, no view types, no scanning implementations, no special-casing the standard library, no hidden copies, `var` stays, closures keep their rules, promises behave like closures with one writer or many readers. Syntax below is new, so it does not pass `ms check` today. Skeptical review (2026-11-21): the rule survives; it found the gaps now covered under Design and Open questions. Counts of affected stdlib sites and fixtures are not yet taken.

## Problem

- Rust decides borrowed results from `native_borrow.rs` (a name list) plus `ResultBorrow` body analysis. The C checker cannot derive it from stdlib declarations, which look alike for `List.get` and `Bytes.view`.
- Interface operations, function values and lambdas always own their result, so a method that returns its field cannot meet an interface and needs `.clone()`.
- A borrowed result that lands in an owning place is silently copied when the type is Clonable (`takes_payload`, `owned_boundary`). Boxed optionals return a copy in some instances only.
- Past holes found by testing and fixed one by one, not a proof of a systemic flaw: a borrow held across a sibling argument (2026-11-01), a `var` parameter captured by a returned closure (#4146), promise borrows lost in containers (#4148, #4150).
- Editing a body can change how every caller treats the result. The structural cost is the port: C cannot derive the mode from declarations.

## Design

The rule: **a non-Copy result borrows from the call's borrowed arguments; `move` before the result type says it is a new value the caller owns.**

```manuscript
fn pick(a: String, b: String) String:       # borrows from a and b
    return a

fn shout(s: String) move String:            # new value
    return s.to_upper()

fn name_of(p: Person) move String:          # clone is written
    return p.name.clone()
```

- Origin: the result borrows from every receiver and non-`move` argument. The caller keeps all of them unchanged while the result lives. A `var` argument or receiver stays exclusive, so `h := buf.head()` blocks reads of `buf` until `h`'s last use. `var x = <borrowing call>` aliases the origin, as today.
- Body check, per `return` path:
  - part of a parameter or a call that borrows from one: allowed without `move`, an error with `move` (fix: `.clone()`); a part of a `move` parameter or of an owned local dead after the return is a partial move, and needs `move`;
  - a new value or a call that returns `move`: needs `move`, otherwise error with a machine-applicable fix that adds `move`;
  - a part of a local or of a temporary: error (`.clone()`, then `move`);
  - mixed paths: error.
- `none` and `error(...)` that carry no borrowed part fit either mode.
- Copy results (`Int`, `Bool`, payload-free enums) have no mode; writing `move` on one is an error. For a type parameter the check runs on the generic signature, so `move T` is always legal and a Copy instance ignores it.
- Nullable types (Chinmay, 2026-11-21): `T?` is the type `T` plus `none`, not a container. A `String?` is a string or `none` in the same place, so a borrowed `String?` is a borrowed string that may be absent, and `m.get(k)` is a free lookup under the default rule. Mode follows `T`, and there is no `opt.view`. In `Result[T, E]` the error is always owned; the success value follows the mode.
- Interface operations, function types and lambdas carry the mode: `fn(String) move String`. An implementation must match exactly, as `var` and `move` parameters do (parameter `move` is already declared on every bodiless signature). A borrowing function is not assignable to a `move` type, nor the reverse: the caller would drop a borrow or leak an owned value. Wrap it in a lambda. A lambda takes it from the expected type, or from its body when there is none.
- Generics: the mode belongs to the signature, never to `T`, so every instance has the same mode and no instance copies.
- Natives are declared in `.ms` (`fn String.to_upper() move String`, `fn List[T].get(i: Int) T?`). `native_borrow.rs` and the default-owned native rule go away.
- A borrowed result of a temporary argument may be used inside its statement; binding or storing it is an error, including `make().trim()`. A string literal is not a temporary (hypothesis, verify). Reject fixtures: `two(label(r), mutate(var r))`, `label(r) + mutate(var r)`, `items_of(r)[idx(var r)]`.
- Storing a borrow in a field, list, `move` argument or `move` result is an error that asks for `.clone()`. The implicit copy and `owned_boundary` go.
- A returned closure that captures a borrowed parameter is an error asking for `.clone()`, not a copy.
- Closures unchanged: a closure that is only called borrows; one that is stored, returned or passed to a `move` parameter owns its captures.
- Promises follow the same rule. A promise in scope borrows; many may read, one may change only what nothing else reads. A promise that leaves the scope owns. The borrow ends when the promise is dropped (the drop joins the work).
- Cost: each owned-result function writes one word. `ms check --fix` adds it to source functions; natives are one audit of the declarations.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `ms-syntax`, `compiler/src/syntax` | `move` before a result type, in `fn` types | parser and formatter round trip |
| `ms-check` ownership, `compiler/src/own` | body vs signature check, origin rule, delete `ResultBorrow`, the fixpoint for results and `native_borrow.rs` | `tests/ownership` accept and reject cases per path above |
| Lowering | read the declared mode (`ret_borrowed`); thunks for interface calls; no instance-dependent copy | e2e under the counting runtime |
| `stdlib/*.ms` | `move` on natives and source functions that return new values | `make copy-check`, `make count-check` |
| Docs and wiki | `references.md`, `OWNERSHIP.md`; replace the 2026-11-01 inference decision | `make docs-check` |

## Alternatives

- Do nothing: bodiless calls stay guessed, soundness depends on four stages agreeing.
- A `borrow` marker on the result, or view types: rejected by Chinmay (hidden complexity, leaks into types).
- Infer from bodies plus a stdlib list (today): unsound for interfaces, slow if every implementation is scanned, rejected.
- Copy when unsure (Go style): hidden copies, rejected.
- Name which arguments a result borrows from (`borrows a`): more precise, one more marker; add only if the all-arguments default measures too strict.

## Stages

1. Syntax, checker rule and fix-it; stdlib migration by `--fix`. Check: `make verify-full`.
2. Declare natives, delete the name table and implicit copies. Check: `make copy-check`, `make count-check`.
3. C walk implements the rule; no oracle diff for these shapes.
4. Promises own or borrow by the closure rule.

## Open questions

- Decided (Chinmay, 2026-11-21): an error is always owned. A `Result` never borrows its error; relaying an error from a borrowed parameter needs `.clone()` or a `move` parameter. Count those sites and the conformance fixtures they change (`testtailresultidentity*`) before approving.
- Boxed optionals and alternatives cannot be a view today. Hypothesis, not verified: a box is already a pointer, so a view is the same pointer without ownership. Verify in `mir_layout.c` before stage 1.
- Parameter `move` is still inferred from bodies for source functions. Recommend: leave it; bodiless signatures already declare it.
- Runner-up: declare the mode only on bodiless signatures (natives, interface methods, function types) and keep inference for source functions. Cheaper to migrate, but keeps the fixpoint and a second rule. Recommend the full rule; Chinmay to confirm.
- `List.slice` and the derived natives (`split`, `keys`) borrow only when elements own nothing. Verify whether that survives as an element-type rule in the checker; it would be the one type-keyed exception.
- Nullable types need three rules: `T??` collapses to `T?` (Chinmay, 2026-11-21: absent and `none` are the same to a user; `has` still tells a missing key from a stored `none`); a nullable scalar is value plus flag and is Copy; today's `Optional[T]` spelling, `?.`, `?` and `if v := x` are rewritten over the new type. Recommend a separate proposal (`proposals/nullable-types.md`) before stage 1.
