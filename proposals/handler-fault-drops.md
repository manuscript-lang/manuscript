# Release a faulted task's values: drops on guarded faults

Status: proposal, 2026-10-26, checked against `d3bf43dd`. Tracks #1325. No language or user-visible behavior changes except that the leak documented on `Network.serve` goes away. Skeptical review: see Review at the end.

## Summary

- A handler that faults is answered with 500 but never releases the heap values its frames own: about 1 MB per fault when it holds a 1 MB string. A client that can trigger a fault can exhaust memory.
- Two gaps cause it: `msrt_unwind_drops` is false for faults, and the `unwind` pass registers cleanups only around calls that can park, not around the operations that fault.
- Change: drops run when a fault leaves a guarded task, and the pass also covers instructions that can fault. Registrations are shared by runs of instructions and hoisted out of loops so the hot path pays almost nothing.
- Cost, measured on a spike: `bench/perf/web` unchanged within run-to-run noise (table below). The naive per-site version cost 60% on `/top`; hoisting is what makes the change viable.
- Decision requested: none beyond review. No new syntax, type, flag, or runtime entry point.

## Status

- Proposal, 2026-10-26. Owner direction from #1325: "A fix needs the unwind pass to cover fault sites and drops to run for guarded faults, with the registration cost measured on `bench/perf/web`."
- Supersedes the "accept the leak" policy documented on `Network.serve` (`stdlib/net.ms`) and in `proposals/taskgroup-request-scopes.md`.

## Problem

Measured on `d3bf43dd` with the fixture below (`tests/e2e/testdata/stdlib/http-fault-leak.ms`): 60 faulting requests grew `resident` by 61,308,928 bytes. `heap_used` stays flat, so the fixture reads `resident`.

```ms
def faulting(exchange: HttpExchange) -> Result[Unit, HttpError]:
    let big = "x".repeat(1000000).get("")
    let xs: List[Int] = []
    let n = xs[big.length()]
    if big.length() + n > 5: return ok(())
    return ok(())
```

Cause, verified:

- `ms-rt/src/fault.rs` `fault_vec` runs the cleanup stack LIFO down to the guard (`run_one_cleanup` stops at `guard_base`), but `UNWIND_DROPS` is set only in `msrt_cancelled`, so the generated `unwind.drop` cleanups do nothing for a fault.
- `ms-mir/src/unwind.rs` registers a cleanup per live owned value only around instructions that `parks_at` (poll, indirect call, non-leaf runtime call, call to a parking function). Index, unwrap, checked arithmetic and `fault` terminators are not covered, so the faulting frame and its callers' frames have nothing registered.
- Callers of the same kind hold values across calls to functions that fault; those calls are not covered either.

Non-goals:

- Values moved out of a field and not yet filled back, values held in stack slots, and values consumed into a half-built aggregate still leak. The pass skips them today for cancellation; the scope is unchanged.
- Faults outside any guard (the process exits) stay free of drops.
- Rust-side leaks in `ms-std-*` natives are untouched.

## Design

One rule: a guarded fault unwinds exactly like a cancellation, and the pass covers every instruction that can leave the function by a fault or a cancellation.

- **Runtime** (`ms-rt/src/fault.rs`): in `fault_vec`, set `UNWIND_DROPS` to `guard_active()` before running the cleanups. `guard_exit` already resets it. An unguarded fault leaves it false.
- **Which instructions** (`unwind.rs`): `exits_at` = `parks_at` or can fault. A new `faulting_funcs` fixpoint marks functions that contain a fault terminator, an op with the `faults` effect, an indirect call or a runtime call, or call a faulting function. Calls to non-faulting functions and pure arithmetic stay uncovered.
- **Terminating faults**: a block ending in `Term::Fault` registers its live owned values at the end of the block with no discard, since it never returns.
- **Shared registrations**: consecutive covered instructions of a block with the same live set share one push and one discard, as long as no hole (a moved-out, unfilled projection) and no `with` open or close (`cleanup.push`, `cleanup.run`) lies between them, since a discard pops every newer entry.
- **Loop hoisting**: for a natural loop with one entry, no hole, and an owned value that is live into the header and consumed nowhere inside the loop, register once in a new block on the entry edges and discard in a new block on each exit edge (and before a `ret` inside the loop). Values defined in the loop or carried through block parameters keep per-site windows. Outer loops are rewritten first so an inner loop adds only what the outer loop lacks.
- **Soundness**: the same argument as today for each window. A registered value is owned, live and unconsumed for the whole window; `list.push`, `rec.set` and `var` parameters consume and return new SSA values, so no registered bits go stale. A hoisted value is unconsumed on every path through the loop by construction, and the discard precedes any consumption on an exit edge.
- **Gate**: the pass still runs only in programs that start tasks or serve (`starts_tasks`), so other programs are untouched.

Before/after for the repro: the handler's `big` is registered before `xs[...]`; the fault runs the cleanup stack, `unwind.drop` frees `big`, `guard_exit` restores the state and the server answers 500.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `crates/ms-rt/src/fault.rs` | `UNWIND_DROPS = guard_active()` on a fault | covered by the e2e fixture |
| `crates/ms-mir/src/unwind.rs` | fault sites, shared windows, loop hoisting | `crates/ms-mir/tests/unwind.rs` |
| `crates/ms-std-net/src/ffi/handler.rs` | comment on `guarded` | none |
| `stdlib/net.ms` `Network.serve` | drop the leak note | `make docs` |
| `proposals/taskgroup-request-scopes.md` | leak note closed | none |
| `tests/e2e/testdata/stdlib/http-fault-leak.ms` | new leak fixture | itself |
| parser, checker, lowering, codegen, formatter, lint, LSP, CLI | unchanged | none |

## Alternatives

- **Do nothing**: documented leak; one request can leak 1 MB, so a client can exhaust memory. Rejected by the issue.
- **Cover every fault site per instruction (no hoisting)**: measured on the spike. `/top?n=10` fell from about 22,300 to 8,000-9,600 requests per second (-60%) because an inlined 1,000-iteration loop registered and discarded per iteration while a string stayed live. Rejected.
- **Free every allocation made since the guard on a fault (request arena)**: unsound when a value escapes into shared state; needs allocation tracking on the hot path. Rejected.
- **Registration at value definition, discard at consumption**: fewer runtime calls, but cleanup discards pop newer entries, so out-of-order consumption needs tombstones and edge splitting everywhere. A larger redesign of a pass whose bugs are double frees; not needed given the measurements.
- **Smallest version**: only set `UNWIND_DROPS` for faults and cover callers' parking calls. Does not fix the repro, whose leak is the faulting frame itself.

## Staging and verification

1. One PR: runtime flag, pass, tests, docs.
2. Checks: `cargo nextest run --workspace`, `make verify`, the new e2e fixture, `bench/perf/web` against the base binary, and a CPU-bound server-program microbenchmark.
3. Go/no-go: `bench/perf/web` within run-to-run noise (10 to 15% on shared machines) on every endpoint, leak fixture below 20 MB growth for 60 faults.

Measured on the spike (4 vCPU shared VM, `run.sh 4`, requests per second, two rounds):

| Endpoint | Base | Per-site only | With hoisting |
| --- | ---: | ---: | ---: |
| `/health` | 93,859 / 95,840 / 99,305 / 93,554 | 80,884 / 83,720 / 72,233 / 85,717 | 84,546 / 90,450 |
| `/user/42` | 85,958 / 89,308 / 85,291 / 82,280 | 75,864 / 88,669 / 86,941 / 80,429 | 98,222 / 97,226 |
| `/top?n=10` | 22,551 / 22,085 / 21,511 / 18,162 | 8,260 / 9,651 / 7,684 / 8,010 | 22,371 / 22,619 |

A server program with a hot checked-arithmetic loop over a held `String` and `List`, plus a 30M-iteration loop allocating a string per iteration: base 0.95, 0.90, 0.92 s; with hoisting 1.01, 1.15, 0.86 s (noise).

## Open questions

None.

## Review

Independent skeptical review, 2026-10-26: the cause and the do-nothing case held. It found one defect: a shared window could span a `with` open and its discard would pop the `with` entry, so a later fault skipped the close. Fixed by ending a window at `cleanup.push` and `cleanup.run`, with a unit test (`ends_a_shared_window_at_a_with_open`). Loop hoisting, `ret` and `fault` exits, and nested-loop discard order checked sound.
