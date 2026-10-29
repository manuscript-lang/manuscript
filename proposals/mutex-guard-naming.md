# One concept for `Shared` and `SharedGuard`: `Mutex` and `MutexGuard`

## Summary

- `Shared[T]` (a refcounted box) and `SharedGuard[T]` (what `lock` returns) read as two unrelated sharing types. The behavior users care about is mutual exclusion, not the refcount.
- Verified: users never write the guard type. `SharedGuard` appears only in `stdlib/sync.ms` and in proposals; every use is `var g = lock(box)` with `g.value`.
- Hiding the guard is not possible: an exported function that returns an unexported type is rejected (`public signature exposes private type`), and `export opaque type` hides the public `value` field the guard exists to expose (checked with `ms check`).
- Proposed: rename the pair to the familiar `Mutex[T]` and `MutexGuard[T]`, constructor `mutex(value)` (was `share`), keep `lock(m)`, `m.get()`; document it as one concept, "a `Mutex` holds a value; `lock` returns a guard whose `value` you read and change". No semantic change.
- Cost: mechanical rename across `stdlib`, docs, about 67 test files, editor data. No compiler logic changes except type-name matches.
- Decision requested: approve the rename, and whether to do it before or after the owner-task decision (`owner-task-state.md`), which may make both names internal.

## Status

Proposal, 2026-10-29, checked against `origin/main` at `69d78f65`. Direction (Chinmay): "having shared and shared guard is confusing, can we just have one", then "write a proposal for that". Nothing implemented.

## Problem

- Two exported names with the same stem suggest two sharing mechanisms; the docs describe `Shared` as "reference-counted value that several owners hold" and the guard as its lock, mixing refcounting with locking.
- The router uses only the shared read (`share`, `get`); every other use locks. The name `Shared` fits the first, not the second.
- Non-goals: removing locks (see `owner-task-state.md`), changing wait or cancellation behavior, the `SharedGuard` glue (#1422).

## Design

- `Shared[T]` becomes `Mutex[T]`, `share` becomes `mutex`, `SharedGuard[T]` becomes `MutexGuard[T]`. `lock`, `get`, `value`, `close` are unchanged.
- Old names are removed, not aliased (pre-1.0; one spelling).
- Docs lead with `Mutex`: copying a `Mutex` shares the value; `get` reads when nobody holds it; `lock` holds it.
- Name matches in Rust follow (`is_source_type("@std/sync.ms", "SharedGuard")`, `starts_with("SharedGuard[")` in `ms-clif`, `ms-lower`, `ms-check`) and are updated mechanically; they stay special cases until #1422 is resolved.

```manuscript
import {Mutex, mutex} from "@std/shared.ms"
import lock from "@std/sync.ms"

export fn main() Int:
    let box = mutex([1, 2])
    var guard = lock(box)
    guard.value.append(3)
    return 0
```

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `stdlib/shared.ms`, `sync.ms`, `bindings.json` | rename types and constructor | stdlib tests |
| stdlib users (`tasks`, `workers`, `processes`, `log`, `router`) | rename | existing fixtures |
| `crates/ms-check`, `ms-lower`, `ms-clif`, `ms-mir` | update type-name matches | `cargo nextest run --workspace` |
| docs, `tests/`, editor and LSP data | rename; generated reference | `make docs`, `make conform` |

## Alternatives

- **Do nothing.** Confusion stays; cost is documentation only.
- **Hide the guard.** Not expressible (see Summary).
- **Keep `Shared`, rename only the guard (`Held`/`Lock`).** Leaves the refcount-versus-lock mismatch.
- **Remove both** (`owner-task-state.md`): larger; this rename is wasted if that lands, which is why ordering is an open question.

## Staging and verification

- One mechanical PR; gates `make verify-full`, search shows no remaining `Shared`/`SharedGuard` outside history and this proposal.

## Open questions

- Do it now or after `owner-task-state.md`? Recommendation: after the stage 2 logger spike, since a public removal makes the rename moot.
- `lock(m)` as a function or `m.lock()` as a method? Recommendation: method, matching the type name; one PR can do both.
