# Release owned values when a guarded call faults

## Summary

- A fault inside a guarded call (HTTP handler today, request scopes next) answers 500 but leaks every heap value its frames own: about 1 MB per fault in the repro below.
- The leak is a remote memory-exhaustion path wherever a client can trigger a fault, and any per-request scope built on `msrt_guard_call` inherits it.
- Two changes make the mechanism work: `fault_vec` sets `UNWIND_DROPS` when a guard is active, and the `unwind` pass registers cleanups at every site that can fault.
- The registration half is too expensive as written: a spike cut `/top` throughput by about 65%. A cheaper registration scheme is needed before anything lands.
- Decision requested: which registration scheme to build (see Alternatives); until then the leak stays documented on `Network.serve` (#1325).

## Status

Proposal, 2026-10-25, checked against `16291da3`. Coordinator direction: own #1325 as a general runtime fix because per-request `TaskGroup` scopes depend on it.

## Problem

- Repro: a buffered handler holds `let big = "x".repeat(1000000).get("")`, indexes an empty list with `big.length()`, then uses `big`. Measured on `6003f16b`, 300 faulting requests: RSS 1.5 MB before, 297 MB after. Freed on a non-faulting path.
- Cause 1: `msrt_unwind_drops` is true only when `msrt_cancelled` unwinds a guarded task (`ms-rt/src/fault.rs`); a fault leaves it false, so generated drop cleanups do nothing.
- Cause 2: `ms-mir/src/unwind.rs` registers cleanups only around calls that can reach a cancellation point (`parks_at`). Faults arise at checked arithmetic, list and optional ops and `Term::Fault`, none of which register anything, and inlining moves callee fault sites into the caller.
- Non-goals: closing OS resources (`with` closers already run on fault), changing which faults are recoverable, and the TaskGroup child-fault catch itself.

## Design

- Runtime half: in `fault_vec`, set `UNWIND_DROPS = guard_active()` before running cleanups, as `msrt_cancelled` does. A fault with no guard still frees nothing (the process exits).
- Compiler half: treat every instruction whose `Op::info().effects.faults` is set, plus `Term::Fault`, as a registration site in `unwind.rs`, in addition to today's park sites.
- Soundness is the existing rule: a value is registered only while owned, live and not consumed by the instruction, and not while a `MoveOut` hole is open.

## Evidence (spike, not committed)

Release build, `sh bench/perf/web/run.sh 5`, same VM, ms rows only, req/s.

| Variant | Leak repro RSS | `/health` | `/user/42` | `/top?n=10` |
| --- | ---: | ---: | ---: | ---: |
| `6003f16b` | 297 MB | 81.5k–92.4k | 80.0k–85.4k | 20.4k–22.4k |
| Every faulting op is a site (both halves) | 2.9 MB | 85.1k–96.1k | 82.5k–86.2k | 7.0k–7.8k |
| Every call is a site, no op sites | 297 MB | 73.2k–74.5k | 66.5k–76.4k | 18.1k–20.9k |

- Faulting-op sites fix the leak and cost about 65% on a CPU loop: each site pushes and discards one cleanup per live owned value.
- Call-only sites leave the leak: the optimizer inlines the faulting callee, so the fault is an inline op. They still cost 5 to 15% on `/health`.
- The cost is registrations per site times live values; the leak fix itself (the runtime half) is free.

### Where the `/top` cost goes (callgrind, run on current main plus the spike)

- Spike binary under `valgrind --tool=callgrind`, ~1,350 `/top?n=10` requests: 1,275M instructions total; the handler 475M (37%), `msrt_cleanup_discard` 395M (31%), `msrt_cleanup_push` 368M (29%).
- 13.6M pushes for ~1,350 requests: about 10,000 per request, one per iteration of the inner selection loop (`pick_after`, inlined; 10 passes x 1,000 ids), with the caller's `out` string live across it.
- Per call: push 27 instructions, discard 29 (out-of-line calls through the isolate indirection and a `Vec` push with a capacity check), against a loop body of about 35 instructions. That is the 2.6x.
- A standalone loop of the same code showed no slowdown, because that program did not run the pass; it is not evidence against the cost.
- Two independent levers follow: register once per live range instead of once per site (cost scales with values, not loop iterations), and make push and discard a few inline instructions instead of ~28 each.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `crates/ms-rt/src/fault.rs` | `fault_vec` sets `UNWIND_DROPS` under a guard | unit test: a guarded fault runs a registered drop |
| `crates/ms-mir/src/unwind.rs` | fault sites become registration sites, by the chosen scheme | MIR unit test; e2e RSS-bounded fault loop |
| `crates/ms-std-net/src/ffi/handler.rs`, `stdlib/net.ms` | drop the leak note once fixed | `http-hardening.ms` |
| `bench/perf/web` | dated section with the cost | rerun |

## Alternatives

- **Do nothing (current).** Documented leak; a client that can fault a handler exhausts memory. Cheapest, and the baseline for the others.
- **Per-site registration (spiked above).** Correct, simple, rejected on cost.
- **Registration at definition, not per site.** Push once when an owned SSA value is defined and tombstone it where it is consumed or dropped; cost scales with values created, not sites. Needs the cleanup stack to allow out-of-order discard, and is unsound for values mutated in place after registration (a bitwise copy goes stale), so it must exclude `var` slots and `Mut` borrows. Hypothesis: a few percent. Needs its own spike.
- **Stack maps.** Record live owned slots per return address; the fault path walks frames (it already does for traces, `describe_frames`) and drops them. No hot-path cost, but needs spill-to-slot guarantees from both Cranelift and LLVM backends. Largest change.
- **Per-request arena.** Free everything allocated during the request. Unsound: values stored into `Shared` state or channels outlive the request.

## Staging and verification

- Stage 1 (free, can land now): the runtime half plus a unit test. It changes nothing observable until sites exist.
- Stage 2: spike live-range registration (excluding values borrowed mutably within the range) and inline push/discard, on `bench/perf/web`; go if `/top` and `/health` stay within noise (10%) and the repro RSS stays flat, else try stack maps.
- Each stage: `cargo nextest run --workspace`, `make conform`, the repro, and a dated `bench/perf/web` section.

## Open questions

- None for the owner yet; the choice is internal to the compiler and runtime. Request-scope work (`TaskGroup`) should treat child faults as leaking until Stage 2 lands.
