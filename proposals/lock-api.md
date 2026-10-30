# Lock API: `Lock`, `Mutex[T]` and `RwLock[T]` as plain types and methods

## Summary

- API first, no new keyword (Chinmay, 2026-10-30). Today `Shared[T]` + `lock(box)` + `SharedGuard[T]` mix sharing, exclusion and payload hand-back in two files and two names.
- Proposed layers, each a plain type with methods:
  - `Lock`: payload-free mutual exclusion. `lock.hold()` returns a `Closeable` hold; closing releases. For the serialization sites (log transport write, worker and process joins).
  - `Mutex[T]`: a value plus exclusion. `m.lock()` returns a guard with `value`. Today's `Shared` + `lock`, renamed and made a method.
  - `RwLock[T]`: later, `read()` and `write()`, once the guard design is settled.
- The guard problem (#1422) comes only from moving a droppable payload out and back. `Lock` has no payload, so it needs none of that machinery; only `Mutex[T]` keeps it.
- Methods fit the loader: a file that mixes native types with bodied code can export bodied methods but not top-level functions (verified 2026-10-30; `lock(box)` as a function cannot move into `shared.ms`). `m.lock()` as a method removes that block, so the two files can become one.
- Decision requested: approve the three-layer shape and the method form; sequencing below.

## Status

Proposal, 2026-10-30, checked against `origin/main` at `69d78f65`. Direction (Chinmay): "api first design, not language keyword"; earlier: "a simple lock interface", "get shared and sync together in one file", "rwlock?". Supersedes the `lock … as …:` block idea in the thread. Related: `owner-task-state.md`, `mutex-guard-naming.md`, `shared-guard-consuming-close.md`. Nothing implemented.

## Problem

- Verified: two exported names (`Shared`, `SharedGuard`) and two modules for one concept; users never write the guard type but cannot hide it (an exported function cannot return an unexported type; `opaque` hides `value`).
- Verified: `lock(box).value.append(2)` on a temporary guard loses the write (box `[1]` stays `[1]` after two such appends).
- Verified: library sites hold a lock across blocking calls (`log.ms` write, `workers.ms` join, `processes.ms` group close) only to serialize; none of them needs the protected value to move.
- Non-goals: cross-thread sharing, new syntax, removing `Shared` read-only sharing.

## Design

```manuscript
# 1. Lock: serialization, no payload
let gate = Lock()
var hold = gate.hold()          # waits while another hold is open
transport.write(text)           # state lives wherever it already lives
hold.close()                    # also on scope end, fault, cancellation

# 2. Mutex: value plus exclusion
let counter = Mutex(0)
var g = counter.lock()          # MutexGuard[Int]
g.value = g.value + 1

counter.get()                   # read a copy of the value when unlocked
counter.set(5)                  # wait, replace, release

# 3. RwLock (later)
let routes = RwLock(table)
let r = routes.read()           # many readers, `r.value` is a borrow
var w = routes.write()          # exclusive
```

- `Lock` and `Mutex[T]` copy cheaply and copies share one lock (refcounted handle, as `Shared` does).
- `hold()` and `lock()` wait in the existing box wait queue; cancellation while waiting leaves the queue, as `Ticket` does today.
- `Lock` is built on a small shared counter. A hold needs no drop of any payload, so no special glue exists for it.
- `Mutex[T]` keeps today's mechanism for droppable payloads. The remaining glue problem is the only open design item, with the options already reviewed (consuming close, or leaving the glue); this proposal does not decide it.
- Requirements for `Mutex`: a temporary guard must either apply its write or be rejected at check time (today it silently drops it).
- Sites: serialization sites use `Lock`; counters, flags, small records and queues use `Mutex[T]`; the router table keeps plain shared reads until `RwLock` exists.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `stdlib/shared.ms` + `sync.ms` | one module; `Lock`, `Mutex[T]`, guard types, methods | stdlib e2e, lock fixtures |
| stdlib users | log, workers, processes to `Lock`; others to `Mutex` | existing fixtures |
| `crates/ms-check` | temporary-guard rule; `begin_lock` recognizes the method form; internal-call restriction path | reject fixtures |
| docs | one concurrency page for the three types | `make docs` |

## Alternatives

- Do nothing: keeps the confusing pair and the temporary-guard bug.
- `lock … as …:` keyword: rejected by direction.
- Owner tasks (`owner-task-state.md`): complementary; not a replacement for short critical sections.

## Staging and verification

1. `Lock` only (new, no migration), with fixtures for fairness, cancellation while waiting and release on fault.
2. Move the three serialization sites; `make conform`, leak check, log throughput not worse.
3. `Mutex[T]` as method form, merge modules, fix the temporary guard; migrate remaining sites.
4. `RwLock[T]`.

## Open questions

- `Lock` and `Mutex` as the names? Recommendation: yes; familiar, and `Shared` stays for read-only sharing.
- Resolve the guard hand-back glue now or leave it? Recommendation: leave it for stage 3, after `Lock` removes most sites from it.
