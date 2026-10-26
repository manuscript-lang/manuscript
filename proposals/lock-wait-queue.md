# Park lock waiters on a wait queue instead of polling

Status: **proposal** (2026-10-26, checked against `origin/main` at `91882327`). Direction (coordinator, relaying Chinmay): park waiters and wake one on `put`; keep the runtime piece a small, general wait-queue primitive and as much logic as possible in Manuscript; remove the #1432 backoff once this lands.

## Summary

- `lock` (`stdlib/sync.ms`) polls with `sleep` while the box is taken, so n waiters cost n wake-ups per poll round (#1431: 100 tasks x 50 short sections, 11.3 s; 1.0 s with the #1432 backoff).
- Change: a waiter queues a runtime token under the box's identity and parks; `SharedGuard.close` wakes the first queued waiter after `put`.
- Runtime adds one small keyed queue of tokens (about 40 lines in `ms-rt`); `Shared` gains `id()`. The queue discipline, cancellation hand-off and the `lock` loop stay in `stdlib/sync.ms`.
- Cost: one extra runtime call per guard release. The uncontended path does not enter the wait loop.
- Decision requested: none beyond the coordinator's direction; no language or user-visible change.

## Problem

- Measured on `origin/main` (release, Linux): `/tmp` probe `l1.ms`, 100 tasks x 50 `with var g = lock(box)` sections each holding a 20 us sleep: 11.3 s wall, 0.8 s CPU. The sections themselves need about 0.1 s.
- Every waiter wakes every poll interval whether or not the box was released, so wake-ups grow with waiters x time held.
- The backoff in #1432 lowers the rate (1.0 s) but keeps polling, adds up to 1 ms latency to a released lock, and still burns wake-ups.
- Non-goals: fairness guarantees, cross-isolate (worker) locking, changing `Shared` semantics or `lock`'s signature.

## Design

- `ms-rt` `waitq.rs` (isolate-local `HashMap<usize, VecDeque<i64>>`):
  - `msrt_waitq_push(key: Int, token: Int)`: appends a token.
  - `msrt_waitq_wake(key: Int) -> Int`: pops the first token, `msrt_channel_post`s it, returns 1 (0 if the queue is empty). A token whose wait ended is dropped by `msrt_channel_post`, as today.
  - `msrt_waitq_remove(key: Int, token: Int) -> Int`: removes the token if still queued, returns 1 if it was.
  - Empty queues are removed from the map; `teardown` clears the map.
- `Shared.id() -> Int` (native, internal like `take`/`put`): the box address. A queue entry lives only while a waiter holds the box through its parameter, so a freed box cannot leave a stale key.
- `stdlib/sync.ms`:

  ```
  # A waiter's place in a box's queue; `close` only matters when the park was cut short.
  type Ticket:
      key: Int
      token: Int
      parked: Bool

  impl Closeable for Ticket:
      var def close() -> Unit:
          if self.parked:
              # Cancelled while parked: leave the queue, or, if this waiter was already
              # chosen, pass its wake on so it is not lost.
              if msrt_waitq_remove(self.key, self.token) == 0:
                  msrt_waitq_wake(self.key)

  export def lock[T](box: Shared[T]) -> SharedGuard[T]:
      while box.locked():
          let token = msrt_channel_token()
          msrt_waitq_push(box.id(), token)
          with var ticket = Ticket(key: box.id(), token: token, parked: True):
              msrt_channel_park(token)
              ticket.parked = False
      return SharedGuard[T](box: box, value: box.take(), held: True)
  ```

  and `SharedGuard.close` calls `msrt_waitq_wake(self.box.id())` after `put`.
- Semantics:
  - No lost wake-up: a waiter checks `locked()`, pushes and parks without yielding in between, and the runtime is single-threaded per isolate.
  - A woken waiter re-checks `locked()`; if another task took the box first it queues again (barging allowed, as with the poll).
  - Cancellation while parked unwinds through `Ticket.close` (a `with` cleanup runs shielded) with `parked` still set, which removes the token or, if it was already chosen, wakes the next waiter, so a cancelled waiter never swallows a wake. A normal wake clears `parked` first, so `close` does nothing (review finding: waking onward on every exit would cascade a wake to every waiter).
  - `Shared` is an isolate-local box; it already cannot be shared across workers, so the queue being isolate-local adds no limit.
  - Barging: a task that calls `lock` while the box is free takes it ahead of a woken waiter; the woken waiter queues again. Starvation under constant load is a non-goal, as with the poll.
  - A box released with no waiters costs one `msrt_waitq_wake` call that finds no entry.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `crates/ms-rt` | `waitq.rs`: push, wake, remove; cleared in `teardown` | unit tests: order, remove, wake after remove, empty map |
| `crates/ms-lower` `sharedbuilder.rs`, `stdlib/shared.ms`, `crates/ms-check` | `Shared.id()` | `shared` conformance fixture |
| `stdlib/sync.ms`, `stdlib/bindings.json` | `Ticket`, queue-based `lock`, wake in `close`; backoff removed | `shared-lock-contention`, `shared-lock-large-payload`, tasks fixtures, leak check |
| `ms-clif`, MIR, `ms-rt` task/token code | unchanged | n/a |
| docs | `Shared.id` is internal like `take`/`put`; `lock` docs unchanged | `make docs` |

## Alternatives

- Do nothing / keep the #1432 backoff: 1.0 s for the repro, still polling and up to 1 ms of release latency (HTTP server).
- Waiter list inside the `Shared` box record: needs the drop glue in `ms-clif/src/lower.rs` to treat one more field specially when the box is dropped while taken, which is the same kind of Rust-side special case #1422 removes.
- `wake` every waiter on release (what `Lane.wake` does): O(waiters) wake-ups per release, the same cost as polling.
- Module-level state in Manuscript: the language has no mutable module globals.

## Staging and verification

- One change: runtime queue + `id` + `sync.ms`. Gates: `cargo test -p ms-rt`, `make conform`, `scripts/leak-check.sh` on shared and tasks fixtures, clippy.
- Added tests: a conformance fixture where a task holds a lock while parked and a second task locks (reported as deadlock), a cancelled waiter that was already chosen (the next waiter still gets the box), and a unit test for token reuse after cancel.
- Review (independent, 2026-10-26): build with changes; the cascade above is fixed here. Its measurement (backoff at 1.04 s, ideal about 0.1 s) is why the bar below is the ideal, not the backoff.
- Go/no-go: the 100 x 50 contention probe within 3x of the ideal (about 0.3 s) with fewer wake-ups than the backoff; `shared-lock-large-payload` (20k tasks) not slower than main; a lock/unlock microbenchmark (uncontended) within 10% of main.

## Open questions

- None that change user-visible behavior.
