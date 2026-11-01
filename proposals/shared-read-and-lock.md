# Shared: one value, several owners, one call at a time

## Summary

- Today a reader learns five names to share one value: `Shared`, `share`, `get`, `lock` and `SharedGuard`. The guard leans on name-matched compiler cases, and nothing shares state across workers.
- Change: `Shared(value)` is used like the value itself. A `var` handle can change it and a `let` handle can only read it, and every call on it runs one at a time. `lock`, the guard, `get` and `share` are removed.
- Language change: member access forwards through a handle, so the examples below do not pass `ms check` today.
- Decision requested: the `let`/`var` rule (open question 1), which changes several stdlib signatures.

## Status

Proposal, 2026-11-01, checked against `85665c98` + branch `claude/project-thread-838z66`. Direction (Chinmay, 2026-11-01): "make super simple for readers"; the "every call runs one at a time" shape is accepted; "var for mutability and let for immutability ... with similar rules of ownership and borrow". Not to be merged until approved.

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

- **Payload.** `T` is a record or alternative you declare: `Shared(Stats(...))`, not `Shared([1])`. To replace a whole list, write `stats.items = []`, so neither the handle nor `=` is ambiguous. The 19 stdlib handles of `List`, `Map`, `Int` and `WriteStream` get small wrapper records.
- **Ownership.** `Shared(value)` moves the value in. Copying the handle adds a holder, and the last holder drops and closes the payload (today's `register_shared_close`).
- **Mutability.** Changing a value through a handle follows the ordinary rules (`OWNERSHIP.md` Mutability): it needs a `var` binding, a `var` parameter (`f(var stats)`) or a `var fn` receiver whose field holds the handle. A `let` handle reads only. `let` still means "this binding cannot change it"; another holder can.
- **Members.** Fields, `[i]` and methods on a `Shared[T]` resolve to `T`'s. `Shared` declares no members of its own, so no name can clash. It takes on none of `T`'s interfaces. A `close` on the payload is a call like any other, and the last holder closes it.
- **One call at a time.** A method that can wait or takes a callback holds the value for its call, with the holder's task id stored in the box. Detect "can wait" with the conservative scan in `ms-tooling/src/lint/tasks.rs:55-96`. Another task's access waits its turn, parked on the box's wait queue (`msrt_waitq_*`), and leaves it on cancel. A cancelled holder releases on its cleanup path. Other calls and field access only check the hold, a flag test with no cleanup entry.
- **Hold check.** Every access through a handle checks the hold: field reads, field writes, calls, and `var` projections (`f(var stats.items)`, `if var e = h[k]?`). The access waits if another task holds the value. It faults if the holder is this task, which catches a callback or a second handle writing under a running call. This is today's `get` fault (`sharedbuilder.rs:150-153`), widened from one method to every access.
- **Reads copy.** A value read out of a `Shared` that outlives its expression is a copy: a binding, an argument, a loop or a match. Today's `get()` already behaves this way (`OWNERSHIP.md:21,30`, fixture `shared-get-copies.ms`). A resource payload cannot be copied, so it is reached only through methods.
- **Atomic steps.** Several changes that must not interleave are one method on `T`. A method that waits, such as a file write, holds the value while it waits. Waiting *for another holder's change* goes outside the call, as `receive` does today (`tasks.ms:212`); inside it, that wait deadlocks.
- **Deadlock.** A call that waits for another call on the same value, or calls back into its own value, faults at once: "Stats is already in a call from this task". Across tasks, the runtime deadlock fault reports it, as it does for `lock` today.
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
| stdlib callers | the 34 lock sites become methods on their payload types (`Lane`, `Inbox`); wrapper records for the 19 std-type handles (14 `List`, 3 `Map`, `Int`, `WriteStream`); sites that hold while waiting stay valid (`Worker.wait` `workers.ms:161`, `stop_child` `processes.ms:465`, log writes `log.ms:104-122`) | `make verify-full` |

## Alternatives

- **Do nothing:** five names and the name-matched glue.
- **Read directly, `lock()` to write** (the previous draft, `lock()` on the branch today): sound with the same fault-on-access check, and it keeps `let` APIs unchanged. The cost is two concepts and a name clash with a payload's own `lock`. This is the fallback if open question 1 is rejected.
- **Writable handles with no per-call hold:** unsound. A call that waits mid-loop over `self.items` races another task's write, which frees the buffer under it.
- **Rust's split (`Rc`, `Arc`, `Mutex`):** four names in front of every reader.

## Open questions

1. `let` reads and `var` writes through a handle. The cost: interfaces that write through a handle field from a plain `fn` become `var fn`, and so must every caller's binding. Affected:
   - `Transport.send`/`receive` (`io/channels.ms:28-30`; `:38` promises they work on a `let`)
   - log `Transport.write` (`log.ms:51-58`)
   - `TaskGroup.spawn` (`tasks.ms:350`), `ProcessGroup.spawn` (`processes.ms:414`), `WorkerGroup.start` (`workers.ms:215`)

   Copying a `let` handle into a `var` one (`var w = view`) would void the rule, so it is rejected. A writable handle comes only from `Shared(...)` or another `var` handle. Recommend accepting the rule with this API fallout. Otherwise, take the fallback in Alternatives.
2. Cost: a flag test per access, plus a cleanup entry only around calls that can wait. Measure with `bench/perf/stdlib/conc_bench.ms` against the latest dated baseline before stage 1 lands.
