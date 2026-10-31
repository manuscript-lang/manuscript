# `if var` borrows a place, not a named method

## Summary

- Problem: `if var x = value` borrows in place only for `get` on a map or list and `first`/`last` on a list, by name, in two Rust lists. `ms-check` (`ownership/walk.rs`, `mutable_payload`) matches `"get" | "first" | "last"`; `ms-lower` (`alias.rs`, `alias_accessor`) matches `(type, name)` and builds each place by hand.
- Any `ref T?` method (`Deque.front`, `Deque.at`, JSON `get`/`at`) is refused with an error that lists the three names, so the list is a language rule that is only true for stdlib natives.
- Change: `if var` borrows the optional place of an indexing form instead of the result of a named method. Names leave both crates.
- Cost: one lowering path for "index with presence test"; `get`/`first`/`last` keep their meaning as reads.
- Decision requested: approve the rule, and which spelling (Open questions).

## Status

Proposal, 2026-10-31, checked against `44a78a68`. Direction (Chinmay, 2026-10-30): "no special casing, everything should be cleanly handled by language rules and semantics". Interaction with `proposals/remove-ref.md` (not yet decided) is addressed below. Not reviewed by a skeptical reviewer yet.

## Problem

- A `ref` result is not a stable place: `Iterator.next()` and `String.trim()` return `ref`, so "returns `ref`" cannot be the test (measured by reading `stdlib/*.ms`: 34 `ref` results, only the list/map accessors are element places).
- Marking projection methods in `stdlib/bindings.json` only moves the same list into data; lowering still needs a per-kind recipe (element index, last index, map entry address).
- With `remove-ref.md`, a method returns an owned value, so a method result can never be written through. Write-through for `if var` must come from a place, not from a result type.
- Non-goals: changing `var x = place`, shared `if let` payloads, or the exclusive-borrow checker.

## Design

- `var x = a.b` and `var x = xs[i]` already borrow a place exclusively (`documentation/core-language/types/references.md`). `if var` gets the same meaning for a place that may be absent.
- Rule: `if var name = P` where `P` is an indexing place on a map or list tests whether the place exists; if so `name` is an exclusive borrow of it, otherwise the `else` branch runs. `P` is a place expression, never a call, so no method name is involved.
- Reads are unchanged: `m.get(k)`, `xs.first()` and `xs.last()` still return owned or `ref` values and stay usable with `if let`.
- Lowering: map and list indexing already produce an entry address or element index in `AStep::Key`/`AStep::Index`; the presence test is the existing `Found::Present` path (`PtrIsNull` for maps, bounds check for lists).
- Without `ref`: nothing in this rule mentions `ref`, so removing it changes no part of `if var`.
- Examples below are **not yet checked** (spelling is an open question) and are marked as new syntax:

```
fn bump(counts: var Map[String, Int], key: String) Unit:
    if var n = counts[key]?:
        n += 1
```

- Rejected: `if var n = f(counts)` where `f` is a call, with the diagnostic "`if var` borrows an indexed place of a map or list; bind a copy with `if let`, then `var x = x.clone()`, or write the changed value back".

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `ms-syntax` | parse the presence-test place if the spelling needs it | parser test |
| `ms-check` `ownership/walk.rs` | `mutable_payload` tests the place form, drops the name match | accept/reject conformance |
| `ms-lower` `alias.rs` | `alias_accessor` takes an index place, not `(type, name)` | `if_var_evaluation` fixture |
| `stdlib/*.ms` | unchanged | |
| docs, formatter, lint, LSP | `conditionals.md` sentence on supported methods replaced by the rule | `make docs`, `make repo-check` |

## Alternatives

- Do nothing: the rule stays a stdlib-only name list; lost on the "no special casing" direction.
- Any `ref T?` method: unsound for `next()`/`trim()` and needs a per-method place anyway.
- Marker in `bindings.json`: moves the list into data; lowering recipes stay per method.
- Make `ref` optionals carry an element address: general for natives, but changes the `ref` representation across checker, lowering and runtime, and is moot if `remove-ref.md` lands.

## Staging and verification

- Stage 1: lowering and checker accept the place form beside the old form; fixtures prove both.
- Stage 2: migrate stdlib, docs and fixtures; delete the name lists.
- Gate: `make verify` plus `if_var_evaluation` in Debug and Release; no leak or allocation count change in `count-check`.

## Open questions

- Spelling of the presence test: `counts[key]?` (recommended; `?` already marks optional values) or a keyword. This is a user-visible language change.
- Whether `else` on a missing key is required, or `if var` alone may fall through as today (recommend: unchanged, falls through).
