# Shared: access only through a lock guard

Status: **proposal, not implemented.** Checked against `ccac1772`.
Direction (Chinmay, 2026-10-25): "yeah let's make it similar to rust" (`Arc<Mutex<T>>`: access only through a guard, released on every exit, no public `take`/`put`).

## Summary

- `Shared.take`/`put` is a manual lock. A task cancelled between them leaves the box marked in use for every holder (probe p13); `Worker.join` hits it today.
- Replace them with `box.lock()`, a guard used with `with`. The guard's `close` returns the payload, and `with` already runs `close` on cancellation.
- One language change: `with ... as var name`, so the block can change the guarded value. Everything else is `stdlib/shared.ms` plus lowering.
- Poisoning is not needed: a fault in a task ends the program (task-groups guide), and a worker has its own heap.
- Decision requested: the `with ... as var` spelling, and fault versus wait when the box is already locked.

## Problem

```
def hold(box: Shared[List[Int]]) -> Int:
    var held = box.take()
    sleep(duration(5000000000))   # cancelled here: put never runs
    box.put(held)
    return 0
```

- After the cancel, `box.get()` faults "shared value is in use" for every holder (`probes/p13_cancelled_take.ms`; verified in `crates/ms-lower/src/sharedbuilder.rs` `shared_method`: `take` sets `taken`, only `put` clears it).
- #1230 frees `held` but cannot clear `taken`.
- Unscoped sites: `Worker.join` waits (`msrt_worker_wait`) between take and put. Every other stdlib site (about 25 in `tasks.ms`, `processes.ms`, `log.ms`, `workers.ms`) has no wait in the window, so they are safe today but easy to break.
- Non-goals: removing `Shared`; blocking locks across threads (a `Shared` never crosses threads).

## Design

```
let box: Shared[List[Int]] = share([1])
with box.lock() as var guard:
    guard.value.append(2)
# guard closed: the payload is back, the box is unlocked
```

- `lock() -> SharedGuard[T]` takes the payload (today's `take`). `SharedGuard[T]` has `value: T` and implements `Closeable`; `close` puts `value` back and clears the mark. Written in `shared.ms`; `take`/`put` become unexported natives used only there.
- `with ... as var name`: the binding may be changed in the block; `close` runs on the binding's final value. The compiler already closes "the current value" of the binding (`with.rs`); the change is parser, checker and docs. A plain `as name` stays immutable.
- Cancellation: the guard is a registered `with` cleanup, so a cancelled task runs `close` and the box is restored with whatever the block had done. This is the p13 fix.
- Fault: the program ends (tasks) or the worker ends with its heap, so no holder can observe a half-changed value. No poison flag. If faults become catchable inside a task, poisoning is added then.
- `get()` stays as a read (`ref T`), faulting while locked, as now.
- Already locked: `lock()` faults "shared value is locked" in v1. Tasks switch only at waits, so this means a lock held across a wait, which is the bug to surface. Waiting instead (as Rust's `Mutex` does) needs a wait queue per box and is deferred.
- Rejected: `lock` without `with` still compiles but the guard is a plain value; a diagnostic is out of scope for v1.

## Worker and process messages (#1249)

- A message type containing `Shared` is accepted today and silently copied by the JSON encoder, so the two sides diverge.
- Stage 4 adds the checker rule the worker proposal already states: `WorkerGroup[In, Out]`, `worker_channel[Send, Receive]` and `ProcessGroup` messages that contain `Shared`, `Weak`, a resource handle, a closure or a `ref` are rejected with "send the value, not a handle to it".

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `crates/ms-syntax` parser, formatter | accept `var` after `as` in `with` | parse and format fixtures |
| `crates/ms-check` | `with` binding mutable when `var`; closer receives the final value | accept and reject fixtures |
| `crates/ms-lower` `with.rs`, `sharedbuilder.rs` | close the binding's current value; `take`/`put` internal | p13 as e2e fixture |
| `stdlib/shared.ms` | `lock`, `SharedGuard`; `take`/`put` unexported | stdlib tests |
| `stdlib/tasks.ms`, `processes.ms`, `log.ms`, `workers.ms` | migrate all take/put sites to `with lock()` | existing e2e |
| docs, `ms guide`, LSP/VS Code snapshots | new API and `with ... as var` | docs checks |
| `ms-rt`, ABI | unchanged | none |

## Alternatives

- Do nothing: p13 stays; rejected by the owner.
- `update(f)` closure: rejected by the owner as the wrong shape for shares; also needs a closure frame covered by cancellation cleanup.
- Native guard with no language change: guard methods mutate through the box like the builders do, but then each mutation is a new native op per payload type. More Rust, against Manuscript first.
- Runtime restores taken boxes on cancel: needs per-task tracking in Rust.

## Staging and verification

1. `with ... as var` (parser, checker, lowering) with fixtures. Gate: existing `with` fixtures unchanged.
2. `lock`/`SharedGuard` in `shared.ms` plus the p13 e2e fixture (fails before, passes after).
3. Migrate the stdlib sites, remove the public `take`/`put`, update docs.
4. Reject `Shared` (and the other handles) in worker and process message types (#1249), with a reject fixture.
Each stage runs `cargo fmt --all --check`, clippy, `cargo nextest run --workspace`, `make repo-check` and the conformance corpus; no platform-specific tests are touched.

## Open questions

- Spelling: `with box.lock() as var guard` (recommended, one new use of an existing keyword) versus a mutable-by-default guard type.
- Already locked: fault in v1 (recommended) or wait.
