# Shared: one value, several owners, one call at a time

## Summary

- Today a reader learns five names to share one value: `Shared`, `share`, `get`, `lock` and `SharedGuard`. The guard leans on name-matched compiler cases, and nothing shares state across workers.
- Change: `Shared(value)` is used like the value itself. A `var` handle can change it and a `let` handle can only read it, and every call on it runs one at a time. `lock`, the guard, `get` and `share` are removed.
- Language change: member access, operators, `for`, `match` and `if let` read through a handle.
- Decision requested: whether a type's own methods change the `Shared` values in its fields (open question 1). Stage 1 implements "yes".

## Status

Stage 1 implemented on branch `claude/project-thread-838z66` (base `85665c98`), 2026-11-01. Direction (Chinmay, 2026-11-01): "make super simple for readers"; "var writes, one call at a time" chosen; "var for mutability and let for immutability ... with similar rules of ownership and borrow"; "not too much special casing in the compiler". Not to be merged until approved.

## Problem

- Measured: 34 `lock` sites and 20 `share(` sites in `stdlib/`; 43 test, doc and bench files import the module.
- Guard special cases (verified): glue matched by name, `ms-clif/src/lower.rs:587-607` (#1422); part-close skip, `ms-lower/src/close.rs:750`; lock-twice lint keyed on `SharedGuard`, `ms-check/src/constfaults.rs:116`; bitwise `put`, `ms-lower/src/sharedbuilder.rs`.
- Sharing across workers is impossible: a `Shared` in a worker message is rejected (`references.md:50`), and each worker has its own heap (`crates/DESIGN.md` decision 4).

## Design

```
var stats = Shared(Stats(hits: 0, names: []))
let view = stats                 # a read-only holder of the same value
stats.hits += 1                  # var handle: changes the one value
stats.record("ada")              # a var fn runs alone on the value
view.hits                        # 1: reads see the current value
view.hits = 0                    # rejected: "view is a let binding; declare it with var to change the shared value"
```

- **Payload.** Any `T`, including `List`, `Map` and `Int`. The type decides what a handle means:
  - Where a `T` is expected, the handle stands for the value: `stats = [1, 2]` replaces the payload, and `let xs: List[Int] = stats` copies it out.
  - Where a `Shared[T]` is expected, it is the handle: `stats = other` points at another value, and `let s = stats` adds a holder.
  - A generic `T` binds the handle, never the payload.
  - `Shared[Shared[T]]` should be rejected so the two readings never collide (not yet implemented).
- **Generic, not named.** The checker takes all of this from a `Proxy` marker in `@std/core.ms` (`impl Proxy for Shared[T]`): `proxy_payload` and `Classifier::proxy`. No `is_std("Shared")` check remains in `ms-check`; the facts `Info.through_shared` and `Info.into_shared` carry the reading to lowering, which keys on them and the box layout.
- **Ownership.** `Shared(value)` moves the value in. Copying the handle adds a holder, and the last holder drops and closes the payload (today's `register_shared_close`).
- **Mutability.** Changing a value through a handle follows the ordinary rules (`OWNERSHIP.md` Mutability): it needs a `var` binding or a `var` parameter (`f(var stats)`). A `let` handle reads only. `let` still means "this binding cannot change it"; another holder can. A type's own methods change the handles in its fields without `var fn` (open question 1). A change through a handle does not change the binding, so an escaping closure (a spawned task) can capture a `var` handle and change the value, or pass it on with `var`.
- **Members.** Fields, `[i]` and methods on a `Shared[T]` resolve to `T`'s. `Shared` declares no members of its own, so no name can clash. It takes on none of `T`'s interfaces. A `close` on the payload is a call like any other, and the last holder closes it.
- **One call at a time.** A source call whose `var` argument or receiver reads through a handle, and a native or interface method that changes it (other than a collection change, which never waits), holds the box for the call: `msrt_shared_hold` records the task and the guard depth in an isolate table, `msrt_shared_release` ends it. Another task's access waits its turn on the box's wait queue (`msrt_waitq_*`) and leaves it on cancel through a cleanup entry. A cancelled or faulting holder's holds end before its cleanups run (`end_abandoned_holds`). The callee changes the payload in place (the `$mem` instance), so a cancelled call keeps its changes so far.
- **Hold check.** Every access through a handle checks the hold: field reads, field writes, calls, and `var` projections (`f(var stats.items)`, `if var e = h[k]?`). The access waits if another task holds the value. It faults if the holder is this task, which catches a callback or a second handle writing under a running call. This is today's `get` fault (`sharedbuilder.rs:150-153`), widened from one method to every access.
- **Reads copy.** A value read out of a `Shared` that outlives its expression is a copy: a binding, an argument, a loop or a match (fixture `shared-reads-copy.ms`). A resource payload cannot be copied, so it is reached only through methods.
- **Atomic steps.** Several changes that must not interleave are one method on `T`. A method that waits, such as a file write, holds the value while it waits. Waiting *for another holder's change* goes outside the call, as `receive` does today (`tasks.ms:212`); inside it, that wait deadlocks.
- **Deadlock.** An access from the task that holds the value faults at once: "a Shared value was used again inside a call on it from the same task". Across tasks, the runtime deadlock fault reports it, as it did for `lock`.
- **Across workers (stage 2).** The same rules apply when `T: Data`. A real mutex replaces the wait queue, and reads copy into the reading worker.
- Hypothesis, not verified; known gaps for stage 2:
  - the arena frees live blocks on exit (`ms-rt/src/alloc.rs:302-305`);
  - messages are JSON (`workers.ms:85-96`);
  - pipes carry only bytes (`pipe.rs:3-6`).

  Stage 2 gets its own proposal.

## Components touched (stage 1)

| Component | Change | Test |
| --- | --- | --- |
| `stdlib/concurrency/shared.ms` | `Shared(value)`; delete `share`, `get`, `lock`, `SharedGuard`, `take`/`put` | `fixtures/e2e/stdlib/shared.ms` |
| `crates/ms-check` | member lookup through `Shared` (`exprs.rs:336`, `calls.rs`, `receivers.rs`); `var` rule on handles; read copies | accept/reject snippets: write through `let`, re-entry |
| `crates/ms-lower` | hold and release around calls through a handle, with cleanup on cancel | cancellation fixture ported from `shared-lock-survives-cancellation` |
| `ms-clif`, `ms-lower` `close.rs`, `constfaults.rs` | delete guard glue, close skip, lint | existing glue tests |
| stdlib callers | the 34 lock sites become methods on their payload types (`Lane`, `Inbox`); the 19 std-type handles (14 `List`, 3 `Map`, `Int`, `WriteStream`) stay as they are; sites that hold while waiting stay valid (`Worker.wait` `workers.ms:161`, `stop_child` `processes.ms:465`, log writes `log.ms:104-122`) | `make verify-full` |

## Alternatives

- **Do nothing:** five names and the name-matched glue.
- **Read directly, `lock()` to write** (the previous draft, `lock()` on the branch today): sound with the same fault-on-access check, and it keeps `let` APIs unchanged. The cost is two concepts and a name clash with a payload's own `lock`. This is the fallback if open question 1 is rejected.
- **Writable handles with no per-call hold:** unsound. A call that waits mid-loop over `self.items` races another task's write, which frees the buffer under it.
- **Rust's split (`Rc`, `Arc`, `Mutex`):** four names in front of every reader.

## Open questions

1. A type's methods change the `Shared` values in its fields from a plain `fn` (implemented). The strict alternative makes about 15 public methods `var fn` (`Transport.send`/`receive`, log `Transport.write`, `TaskGroup.spawn`, `ProcessGroup.spawn`, `WorkerGroup.start`), and every caller's binding `var`.
2. Copying a `let` handle into a `var` one (`var w = view`) voids the `let` rule; rejecting it is not implemented, and stdlib types built from `let` handles rely on it today.
3. Cost, measured. `bench/perf/stdlib/conc_bench.ms`, release build, median of 7, shared cloud VM, base `85665c98` vs this branch: the base's `lock.uncontended` (lock, `+= 1`, guard drop) 12.9 ns/op; `shared.update` (`box += 1`, no hold) 2.7 ns/op; `shared.call` (`bump(var box)`, one hold) 9.0 ns/op. The task and channel cases moved within run-to-run noise (up to 2x on this machine).
