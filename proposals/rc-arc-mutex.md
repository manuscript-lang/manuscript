# Rc, Arc and Mutex replace Shared

## Summary

- Today you change shared state through `Shared[T]` plus `share`/`get`/`lock`/`SharedGuard`. Nothing shares state across workers, and the guard is held together by name-matched compiler cases.
- Change, the Rust split: `Rc[T]` is a transparent, **read-only** refcount on one worker. `Arc[T: Data]` is the same across workers. `Mutex[T]` is the only way to change shared state, and its guard is built on a general field move-out (#1422).
- Decision requested: read-only `Rc` + `Mutex` (this proposal) over a writable lock-free `Rc`, which review found unsound (see Alternatives).

## Status

Proposal, 2026-11-01, checked against `85665c98` + branch `claude/project-thread-838z66` (step A: `sync.ms` merged into `shared.ms`, primitives private). Direction (Chinmay, 2026-11-01): "add a simple Rc and Arc types in stdlib and get rid of shared"; "Rc ... exposes the value methods directly ... no locks needed". This reverses the "no locks" part for writes: Open question 1. Skeptic review: the writable-`Rc` draft did not hold; this version follows it. Not to be merged until approved.

## Problem

- Five names for one idea: measured 34 `= lock(` and 20 `share(` sites in `stdlib/`, and 43 test, doc and bench files import the module.
- Guard special cases (verified): name-matched glue `ms-clif/src/lower.rs:587-607` (#1422), part-close skip `ms-lower/src/close.rs:750`, lock-twice lint `ms-check/src/constfaults.rs:116`, bitwise `put` `ms-lower/src/sharedbuilder.rs`. Handle checks keyed on `Shared` (they stay, renamed): `classify.rs:83`, `contracts.rs:756`, `walk.rs:451`, `ms-lower/src/call.rs:531`, `cx.rs:432`, `verify.rs:1133`.
- Sharing data across groups is impossible. A `Shared` in a worker or process message is rejected (`references.md:50`), and each worker has its own heap (`crates/DESIGN.md` decision 4).

## Design

```
let config = Rc(Config(port: 8080, names: ["a"]))
let other = config                 # a second holder, same payload
config.port                        # 8080: reads go to the payload
config.names.length()              # read-only methods are fine
config.port = 1                    # rejected: "an Rc is read-only; hold the value in a Mutex to change it"

let hits = Rc(Mutex(Counter(total: 0)))
var held = lock(hits)              # today's waiting lock, renamed
held.value.total += 1              # back in the box when `held` closes
```

- `Rc(value)` moves the value in. Copying adds a holder, and the last holder drops (and closes) the payload, as today's `register_shared_close` does.
- Reads through `Rc[T]` resolve to `T`'s members: fields, `[i]`, and methods without a `var` receiver. A binding, loop or match of such a read gets a temporary copy, the same rule as `get()` today (`OWNERSHIP.md:21,30`). Resource payloads can't be copied, so they are read only through a `Mutex`.
- Writes are rejected: field writes, `var fn` calls and `var x = rc.f`. `let` stays immutable, including its contents (`DESIGN.md:7`), so the language rule doesn't change.
- `Mutex[T]` on one worker is today's `lock`/`SharedGuard`, a cooperative waiting lock that survives cancellation, unchanged in behavior. Its guard hands `value` back with a field move-out of `self` in `close` (#1422), so the glue, the part-close skip and the bitwise `put` go away.
- `Arc[T: Data]` is the read rule above across workers, with an atomic count. Inside it, `Mutex` waits across workers by parking the task, through the per-isolate wake inboxes (`DESIGN.md` decision 4).
- Removed names: `Shared`, `share`, `get`, `SharedGuard` (it becomes `MutexGuard`), and the private `take`/`put`/`locked`/`id` once `Mutex` owns them.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `stdlib/concurrency/shared.ms` | `Rc`, `Mutex`, `MutexGuard` (stage 1); `Arc` (stage 2) | e2e `rc-*`, `mutex-*`; cancellation fixture ported |
| `crates/ms-check` | read-through member lookup on `Rc`/`Arc` (`exprs.rs:336`, `calls.rs`, `receivers.rs`); write rejection; `close` field move-out (#1422) | conformance accept/reject |
| `crates/ms-lower`, `ms-clif` | in-place reads; delete guard glue and close skip | existing glue and `shared-*` tests |
| `ms-rt` | stage 2 only: payload in system memory, atomic count | Rust unit, leak-check |
| stdlib callers, docs, LSP snapshots | migrate 34 lock and 20 share sites | `make verify-full` |

## Alternatives

- **Do nothing:** five names, the name-matched glue, and no sharing across workers.
- **Writable lock-free `Rc`:** unsound. A call through an `Rc` that waits while iterating `self.items` races a write from another task. Making it sound needs an access mark on every write and every call, which is an implicit read-write lock. That lock deadlocks semaphore and queue types (`rc.acquire()` waits for `rc.release()`), and it breaks `let` immutability.
- **Rename `Shared` to `Rc` and keep `get` + `lock`:** the smallest change. It keeps the guard hacks and gives no transparent reads.
- **A shared heap across workers:** breaks per-isolate arenas.

## Stages

1. `Rc` (read-only) + `Mutex` on one worker with #1422's field move-out; stdlib migrated; guard special cases deleted. Gate: `make verify-full`.
2. `Arc[T: Data]` + cross-worker `Mutex`. Hypothesis, not verified, with known gaps:
   - a dying arena frees its live blocks (`ms-rt/src/alloc.rs:302-305`), so payloads need copy glue that allocates in system memory;
   - worker messages are JSON (`workers.ms:85-96`) and pipes carry only bytes (`pipe.rs:3-6`), so an `Arc` in a message needs a handle encoding;
   - an unread queued message leaks its count.

   Gate: 4 workers increment one counter 10k times each to 40k, and leak-check stays clean. It gets its own proposal after stage 1.

## Open questions

1. Writes through `Rc` without a lock (Chinmay's "no locks needed"): recommend no, for the reasons in Alternatives. `Rc[Mutex[T]]` is the write path, as in Rust.
2. Spelling of `Rc(Mutex(x))` on one worker: recommend keeping it. One write path everywhere beats a single-worker shortcut.
