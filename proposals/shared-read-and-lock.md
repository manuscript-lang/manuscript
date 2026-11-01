# Shared: read it directly, lock it to change it

## Summary

- Today a reader learns five names to share one value: `Shared`, `share`, `get`, `lock` and `SharedGuard`. Nothing is shared across workers, and the guard leans on name-matched compiler cases.
- Change: one type and one method. `Shared(value)` constructs it, and reads go straight to the payload (`stats.hits`). `stats.lock()` is the only way to change it. Later, the same API works across workers when `T: Data`.
- Decision requested: approve stage 1 (the API, plus #1422 to retire the guard glue); stage 2 is listed for direction only.

## Status

Proposal, 2026-11-01, checked against `85665c98` plus branch `claude/project-thread-838z66`. Direction (Chinmay, 2026-11-01): "we need to make super simple for readers of manuscript"; one name, one verb accepted, with `lock` as a method so readers find it. A Rust-style `Rc`/`Arc`/`Mutex` split and a writable lock-free `Rc` were considered and dropped (Alternatives). Skeptic review applied. Not to be merged until approved.

## Problem

- Measured: 34 `lock` sites and 20 `share(` sites in `stdlib/`; 43 test, doc and bench files import the module.
- Guard special cases (verified): name-matched glue `ms-clif/src/lower.rs:587-607` (#1422), part-close skip `ms-lower/src/close.rs:750`, lock-twice lint keyed on `SharedGuard` `ms-check/src/constfaults.rs:116`, bitwise `put` `ms-lower/src/sharedbuilder.rs`.
- Sharing across workers is impossible: a `Shared` in a worker message is rejected (`references.md:50`), and each worker has its own heap (`crates/DESIGN.md` decision 4).

## Design

```
let stats = Shared(Stats(hits: 0, names: []))
let other = stats                  # a second holder of the same value
stats.hits                         # read directly
other.names.length()               # read-only methods too
stats.hits += 1                    # rejected: "a Shared value is read-only here; change it with `var s = stats.lock()`"
var s = stats.lock()               # waits while another task holds it
s.hits += 1                        # stored back when `s` goes out of scope
```

- `Shared(value)` moves the value in, and copying the handle adds a holder. The last holder drops the payload, closing it if it is a resource (today's `register_shared_close`).
- Reads on a `Shared[T]` resolve to `T`'s members: fields, `[i]`, and methods without a `var` receiver. A binding, loop or match of a read gets a temporary copy, as `get()` gives today (`OWNERSHIP.md:21,30`). A resource payload can't be copied, so it is read through `lock()`.
- Writes go only through `lock()`: a field write, a `var fn` call or a `var x = stats.f` is rejected with the diagnostic above. `let` stays immutable including its contents (`DESIGN.md:7`), and reads can't race a write.
- `lock()` is today's waiting lock (already a method on the branch, with all stdlib sites migrated). Its guard is unchanged in behavior: `s` closes at scope end, on early return and on cancellation, and `s.close()` ends it early.
- The guard hands `value` back through a general field move-out of `self` in `close` (#1422). That deletes the name-matched glue, the part-close skip and the bitwise `put`. The lint keeps working through the guard's type.
- Removed names: `share` and `get`. `SharedGuard` stays as the guard's type, but users never write it.

### Stage 2, direction only: across workers

- The same `Shared[T]` and `lock()`, when `T: Data`. Reads copy into the reading worker, and `lock` parks the task (not the thread) on the per-isolate wake inboxes.
- Hypothesis, not verified. Known gaps:
  - a dying arena frees its live blocks (`ms-rt/src/alloc.rs:302-305`), so the payload needs copy glue that allocates in system memory;
  - worker messages are JSON (`workers.ms:85-96`) and pipes carry only bytes (`pipe.rs:3-6`), so a handle needs an encoding;
  - an unread message leaks its count.
- It gets its own proposal after stage 1.

## Components touched (stage 1)

| Component | Change | Test |
| --- | --- | --- |
| `stdlib/concurrency/shared.ms` | `Shared(value)` constructor; drop `share`, `get` | `tests/conformance/fixtures/e2e/stdlib/shared.ms` |
| `crates/ms-check` | read-through member lookup on `Shared` (`exprs.rs:336`, `calls.rs`, `receivers.rs`); write rejection; `close` field move-out (#1422) | conformance accept/reject snippets |
| `crates/ms-lower`, `ms-clif` | in-place reads; delete guard glue, close skip, bitwise `put` | `shared-lock-*`, `shared-get-copies` ported |
| stdlib callers, docs, LSP snapshots | migrate 20 `share(` and every `.get()` site | `make verify-full` |

## Alternatives

- **Do nothing:** five names, the name-matched glue, and a free `lock` that readers can't discover.
- **Rust split (`Rc`, `Arc`, `Mutex`):** four names and Rust's taxonomy in front of every reader; the cost difference is better kept in the runtime.
- **Writable lock-free `Shared`:** unsound across waits. Fixing that needs an implicit read-write lock on every write and call, which deadlocks queue and semaphore types and breaks `let` immutability.
- **Keep `get()` and add only the method `lock()`:** the smallest step, and it is already on the branch. Direct reads remove `get` from the 34 read sites.

## Open questions

1. Read-through member lookup is a checker rule for one std type. Recommend writing it as a std `Deref[T]` contract that only bundled modules may implement, so member lookup does not name `Shared`.
