# Read holds on `Shared`: many readers or one writer

## Summary

- A call that only reads a `Shared` payload takes no hold, so another task can replace or change the payload while that call is parked. The reader then uses freed memory: the repro below segfaults, and valgrind reports an invalid read.
- Change: every call that borrows through a `Shared` takes a read hold. Read holds stack, and a writer waits until they end. A lent result through a `Shared` is copied out, so no borrow of a payload outlives its call. This is the runtime form of the borrow rule: many `let` readers or one `var` writer.
- `Shared` stays local to one isolate, so a hold is a counter in the box on the isolate's own scheduler: no atomics and no OS lock.
- Decision requested: a write to a value inside a read call on that same value now faults (Open questions).

## Status

Implemented on the branch (not merged), 2026-11-01; proposed against `claude/project-thread-838z66` at `126ae56a`. Chinmay: "only few things need to cross thread boundary, everything else runs in a single thread, we wanna minimize locking". Skeptical review: build with changes. Those changes are applied here: every call path, lent results, holds matched by task, and no writer preference.

## Problem

Measured (`ms run`, debug and release, Linux). A task parks inside a read call while another task replaces the payload:

```
fn slow(n: Notes) String:
    sleep(milliseconds(50))
    return n.names[0]              # n borrows the old payload, which is freed
...
group.spawn(fn var ch: say(slow(reader)))
group.spawn(fn var ch:
    sleep(milliseconds(10))
    writer = Notes(["replaced-name-long-enough-for-the-heap-too"]))
```

- It exits 139 for a free function, a method (`reader.slow_first()`) and an interface method (`reader.n.slow_name()`). Without the write, it prints the name.
- A lent result fails too, with no call parked: `let xs = first_of(reader)`, then `sleep`, then `xs[0]`. So does `slow(first_of(reader))`.
- Cause (verified): `eval_args` (`crates/ms-lower/src/call.rs:173`) records only `var` positions in `Args::places`, and `shared_hold` holds only those. `contract_call` (`call.rs:816`) takes no hold. A lending call through a `Shared` returns a borrow (`call.rs:504`).
- Plain `let` of a field, `for`, `if let`, `match`, `Map.get` and closures copy, so they are not affected (probed).
- Non-goals: sharing a `Shared` across isolates (workers stay shared-nothing, `crates/DESIGN.md` decision 4), and fairness between waiting readers and writers.

## Design

The box's in-use flag (field 1 of the `Shared#…` record, `sharedbuilder::handle_ty`, used only by `Shared`) becomes an `Int`: `0` free, `n > 0` for `n` read holds, `-1` for a write hold or an in-place update.

- **One helper for every call.** `shared_hold(places, mode)` runs for source, interface (`contract_call`), native, and indirect (`closure.rs`) calls. Each argument and receiver that reads through a `Shared` (`shared_root`) takes a read hold. A `var` position, or a native that changes its receiver, takes a write hold.
- **Hold, then read.** The holds are taken before the arguments are loaded, so an argument that parks (`f(reader.names, slow())`) cannot leave a stale borrow.
- **Read hold.** It waits while the state is `-1`, then adds 1, and its release subtracts 1. **Write hold:** it waits until the state is `0`, then sets `-1`.
- **Which calls write.** A position is held for a change only when the callee's body changes its memory (`Cx::changed`, the body-derived part of `infer_mutated`). A `var fn` that only stops native work, such as `FileWatcher.close`, takes a read hold. So closing a watcher from another task still wakes a pending `next()`; with a write hold it waited for that `next()` forever (`native-bindings` e2e).
- **Field reads** (`view.hits`) wait while the state is `-1` and take no hold, since a load cannot park.
- **Lent results.** The checker records a lending call whose source reads through a `Shared` in `owned_lends`, the same fact a temporary source uses (`walk.rs:3441`), so lowering copies the result out before the hold ends. This reuses an existing path and adds no new one.
- **Same task.** A read inside the task's own read proceeds, so a callback may read the value it was given. A write inside its own read or write faults with the existing message. `msrt_shared_wait` checks all of the running task's holds on the key.
- **Holds by task.** `Hold` (`crates/ms-rt/src/channel.rs`) gains a mode, and `hold_of` matches on the task as well as the key. `end_abandoned_holds` subtracts a cancelled or faulted reader's hold.
- **Wake-ups.** When the state returns to `0`, every waiter on the key wakes and checks again (one post each, on one scheduler thread).
- **Cost.** A read call through a `Shared` gains the two runtime calls that a `var` call already pays. Calls that do not read through a `Shared` are unchanged. Measured with `ms bench bench/perf/stdlib/conc_bench.ms --filter shared --samples 15`, release, on the same cloud VM class as `baseline-2026-10-28.md`. Before is `96c566d7` and after is this change, each median taken over alternating runs:

  | Bench | Before | After |
  | --- | --- | --- |
  | `shared.read_call` (new: a read call on a heap payload) | 7.0 ns | 18.5 ns |
  | `shared.call` (`var` call) | 9.3 ns | 13.7 ns |
  | `shared.update` (`box += 1`) | 2.8 ns | 2.4 ns |

  `shared.call` costs more because release now finds the running task's own hold. `msrt_waitq_wake_all` returns early when nobody is waiting, which is what keeps `shared.update` from regressing.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `crates/ms-lower/src/call.rs`, `sharedbuilder.rs`, `closure.rs` | read places in every call path, holds before loads, state word | e2e: free fn, method, interface, indirect fn, nested argument; writer waits |
| `crates/ms-check/src/ownership/walk.rs` | lending through a `Shared` goes in `owned_lends` | e2e: lent result held across a park |
| `crates/ms-rt/src/channel.rs` | hold mode, holds matched by task, read release, wake all | e2e: cancel a parked reader, then write |
| `stdlib/concurrency/shared.ms`, wiki | doc comment: reads run together, a change runs alone | `make docs`, repo-check |
| `bench/perf/stdlib/conc_bench.ms` | read call through `Shared` in a loop | before/after against `baseline-2026-10-28.md` |

## Alternatives

- **Do nothing.** It leaves a use-after-free that any task with a `let` handle and a `sleep` reaches.
- **Read calls take the write hold.** It would serialize readers, and a callback reading its own value (`m.ms` prints `2` today) would fault.
- **Copy the payload into read calls.** O(payload) per call, since plain data is not reference counted (decision 1). Big maps are the reason to use `Shared`.
- **Hold only when the callee can park.** This needs a "may park" effect that does not exist. It could be added later as an optimisation, without changing these semantics.
- **Writer preference** (queued writers block new readers). Dropped: two readers waiting on each other with a writer queued deadlock, and it needs a count of waiting writers.

## Open questions

- A change to the value inside a read call on it (`shared.count_after(fn: other.bump())`) faults, as a `var` borrow does while a `let` borrow is live. Recommend: fault. A payload with no heap memory (`Stats(hits: Int)`) takes no hold, so `stats.total(fn: w.hits = 7)` behaves as before.
