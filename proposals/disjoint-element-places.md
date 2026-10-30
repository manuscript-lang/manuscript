# Disjoint element places: loop-index offsets, and why not `split_at`

## Summary

- Problem: after literal indexes (#1992), `bump(var xs[i], var xs[i + 1])` in a range loop is still rejected as overlapping, though the two elements can never be one.
- Change (checker only): an element step may be an offset from an immutable, provably non-negative `Int` binding; same base with different offsets is disjoint.
- Non-change: no `split_at`. It needs a borrowed mutable view type (a language change); recommend not building it now.
- Cost: one `Step` variant, one proof rule, no lowering or runtime change. Decision requested: confirm `split_at` stays out.

## Status

- Proposal, 2026-10-30, checked against main f25da1e5 (per-field liveness #1997 landed).
- Direction (Chinmay): "Allow provably disjoint accesses; conservatively reject unresolved overlap initially." "Model access to fields and elements uniformly."

## Problem

Verified at f25da1e5 with `ms check`:

```ms
fn bump(var a: Int, var b: Int) Unit:
    a += b

fn f(var xs: List[Int]) Unit:
    for i in 0..xs.length() - 1:
        bump(var xs[i], var xs[i + 1])  # rejected today: argument `xs[..]` ... overlaps argument `xs[..]`
```

- Cost: stencils, prefix sums and pairwise updates need `xs.swap` or an index copy through a temporary.
- Non-goals: `xs[i]` with `xs[j]` for unrelated `i`, `j`; maps; ranges (`xs[a..b]`); any new type.

## Design

- Rule: `Step::Offset(base, k)` is the element at `base + k`, where `base` is a binding uid and `k` a literal. Two offsets with the same base and different `k` are disjoint. Every other element pair keeps today's rule (`Index`/`Offset`/`Element` may alias).
- A binding is a valid base only if both hold, and either failure falls back to `Step::Element`:
  - It is immutable for its whole scope: a range-loop variable (loop variables cannot be assigned).
  - It is non-negative: the loop range's start is a non-negative literal. Index `i + k` with `k >= 0` is then non-negative too; `i - k` is not a valid offset.
- Why non-negativity matters: a negative index counts from the end, so for `i = -1` and a one-element list, `xs[i]` and `xs[i + 1]` are the same element. A parameter `i` therefore stays rejected:

```ms
fn g(var xs: List[Int], i: Int) Unit:
    bump(var xs[i], var xs[i + 1])  # stays rejected: i may be negative
```

- Soundness argument: within one loop iteration the base value is fixed and shared by every place built from it. Different non-negative offsets of one value are different indexes of the same list, so different elements. A borrow cannot outlive the iteration that named the base.
- A change to the list itself (`xs.append`) still overlaps every element place by prefix, so resize-under-borrow stays rejected.
- `Place::overlaps` stays the single comparison used by overlap checks, borrow conflicts and per-field liveness; no second rule set.

## Why not `split_at`

- `let (a, b) = xs.split_at(k)` needs two simultaneously live mutable views of one list. Manuscript has neither tuples nor a view type; `List.slice` copies.
- A view type would reach types, ownership classification, lowering (fat pointers), `for` iteration, formatting and docs, and interacts with the open borrowed-iterator proposals. That is a language change, not a checker rule.
- The element-level rule above already covers the in-place pairwise cases `split_at` is usually used for. `swap(i, j)` and `copy_within` cover the rest.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `crates/ms-check/src/ownership/places.rs` | `Step::Offset`, `may_alias` arm | accept/reject ownership corpus |
| `crates/ms-check/src/ownership/walk.rs` | `element_step` derives offsets from range-loop bindings | same |
| parser, lowering, codegen, runtime, stdlib | unchanged | `make conform` stays 100% |
| `documentation/core-language/types/references.md` | one sentence | docs check |

## Alternatives

- Do nothing: loses the pairwise in-place pattern; cheap to keep and reasonable if no program needs it.
- Prove `i != j` from any dominating condition: needs a range or relational analysis the checker lacks; unbounded cost for the gain.
- Dynamic check (fault if indexes are equal at runtime): adds runtime work to a hot path and defers a static error.
- `split_at` with a view type: see above; deferred.

## Staging and verification

- One stage: land the rule with tests. Accept: `xs[i]`/`xs[i + 1]` in `for i in 0..n`, and in `var a`/`var b` borrows. Reject: same offset, parameter base, `var` base, `xs[i]`/`xs[j]`, negative start, `i - 1`.
- Gate: `cargo test -p ms-check`, `make conform`, `make repo-check`, native run of an accepted program on Debug and Release.

## Open questions

- Keep `split_at` out until a view type is designed? Recommendation: yes.
