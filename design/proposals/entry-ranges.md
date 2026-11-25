# Entry ranges for parameters and closure captures

* Status: **Implemented** (2026-11-25, `main` at 1e2b692)
* Authors: Claude, for Chinmay
* Implementation: this change

## Summary

- Problem: the range pass starts every function with its parameters and captures at "any `Int`", so a value that is 0..127 at every call site still pays signed-remainder fixups, a negative-index path and sign checks.
- Change: a module step joins the intervals that callers and `closure.new` sites pass, and seeds the range pass with them. No language change.
- Decision requested: none (compiler-internal); review of the design.

## Motivation

`bench/perf/suite/workers`: `chunk_checksum(chunk)` is called from a promise closure whose capture is the loop variable of `for chunk in 0..128`. Rust's version of the same loop knows `chunk` is non-negative (it comes from a `usize` range), so `x % 256` is an unsigned remainder and `hist[...]` has one compare. Manuscript executes 1129M instructions against checked Rust's 769M (callgrind, 2026-11-25).

Evidence that the lost fact is the whole gap: replacing `chunk * 7919 + 1` with `bit_and(chunk, 127) * 7919 + 1` in a copy of the program gives 770M instructions (equal to Rust, same checksum) and 99 ms against 105 ms on one thread, 31 ms against 35 ms on four (min of 7, noisy VM).

## Proposed solution

No source change. A function that is only called directly, or is only used as a closure body, gets an interval per integer parameter and per integer capture, the join over every place that calls it or builds its closure.

```manuscript
fn weight(i Int) Int {
    return i % 256   // i is 0..127 at every call: no negative path
}

fn main() Void {
    var total = 0
    for i in 0..128 {
        total += weight(i)
    }
    print(total)
}
```

LLVM already does this after inlining; it cannot do it through a promise, a closure stored in a list, or a function the inliner kept out of line.

## Detailed design

- **Facts.** `MirFunc` gets `RgItv *entry` (one interval per parameter and per non-cell capture; null means top), in the module arena like `exact`. A closure's non-capture parameters (`id`, arguments from `call.ind` or the runtime) stay top.
- **Where.** `range` runs once, inside `function_passes`, after the early steps (inlining and `unwind sites`) have fixed the call sites. A module step `entry_ranges` runs between them. The late steps (`fuse`, `exit_drops`, `unwind pairs`, `thread`, `fastpaths`) run after `range` and add only runtime calls and calls of drop and close functions with owned values, never an `Int` argument to a seeded callee. This is an invariant of those passes, not checked. The step runs the range analysis on each function and reads the interval of each argument at `MOP_Call` sites and of each captured operand at `closure.new`, and joins them into the callee's table.
- **Fixpoint.** Tables start empty (callee unreached) and only grow by join; a function is revisited when a table it reads changed, and an entry that has changed four times goes to top, so it ends. The `workers` chain (loop, `start_chunk`, `closure.new`, `closure.cap`, `chunk_checksum`) is three hops and settles in order.
- **Soundness: every use known.** A function gets a table only if every reference to it is a direct `MOP_Call` or, for a closure, a `closure.new`. The step reuses the root enumeration of `opt_inline_dead.c`, extended to the places a function id lives outside instructions: `default_fn`, `MirCaptureCloser.func`, `close_exit`, `slot_result`, `MirDescGlue.eq/hash`, `MirVtable.methods/close_drop`, the module `entry` and `close`, `FuncAddr`, and exported test entries. Any such reference leaves the function top. Release builds keep functions internal (#7124); debug builds export them, so the step treats every function as referenced there. The pipeline is the same, only the table differs.
- **Soundness: captures.** Only a plain capture read by `closure.cap` is seeded: it is copied in at `closure.new` and nothing writes it. A mutated `var` capture is a cell read through `closure.cap_addr` and stays top.
- **Telling LLVM.** Seeding lets the range pass fold a user's own guard (`while at >= 0 and ...` in `PriorityQueue.sift_down`), and LLVM then loses the only sign it could see: `graph` got 2.7% slower in the first prototype. So the emitter also states what the range pass proved: `llvm.assume` of the entry interval of each seeded parameter and capture, and of each integer block parameter the pass bounded (`MirFunc.facts`, set by `range`). With these `graph` is 2.3% faster than before the change. Facts are recorded only in functions that were seeded: recorded everywhere they cost `wordfreq` +0.7% instructions (one nonnegative loop phi changed LLVM's loop) and bought `exprparse` -1.9%; seeded-only keeps every program at or below its old count.
- **Seeding.** `rg_fa_init` sets `base` of a seeded parameter to its interval instead of `RG_TOP`, and `closure.cap` evaluates to its entry interval. The existing negative-index and signed-remainder rewrites then fire without change.
- **Inlining.** A copy made after the step has no table; the step runs last, so none are made.
- **Cost.** Each function is analyzed once per revisit; the fixpoint is bounded by the entry-change cap. Measured on the compile-time suite before merge; the budget is no regression beyond noise on `bench/perf/compile-time`.

## Review (skeptical subagent, 2026-11-25)

Found: a three-round cap would reset the `workers` chain to top; the reference scan missed ids outside instructions; late passes add call sites; non-capture closure parameters are not joined; mutated captures are cells; the 770M figure comes from a changed callee, so a prototype must reproduce it. All are folded in above. Not adopted: clone or inline single-caller callees, which does not help when callers are several closures and leaves the fact unavailable through `closure.new`.

## Fit with the language

- **Memory model:** no change.
- **Agent ergonomics:** no source change; programs get faster without a type annotation.
- **Names and syntax:** none.
- **Platforms:** same on all.

## Measured benefit

Callgrind instructions, same machine, all 23 suite programs against its parent: `workers` 1129M to 771M (-31.7%, equal to checked Rust's 769M), `graph` -2.4%; every other program within 0.15% (`jsonrt` +0.06%, `pargroup` -0.14%).

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `src/compiler/mir/mir.h` | `entry` table on `MirFunc` | MIR verifier: length equals parameters plus captures |
| `src/compiler/opt/opt_entry_range.c` (new) | module step, fixpoint | `tests/checks` MIR check: callee with 0..127 caller loses its negative path; callee with an unknown caller keeps it |
| `src/compiler/opt/opt_range*.c` | seed entry parameters and `closure.cap` | existing range fixtures unchanged |
| `src/compiler/emit` | `llvm.assume` for entry intervals and block-parameter facts | `workers` instruction count |
| `bench/perf/results.md`, wiki | dated result, page | `repo-check` |

## Alternatives considered

- Do nothing: `workers` stays 1.47x checked Rust in instructions, 1.14x in wall time.
- Inline `chunk_checksum` into the closure: it is 100+ instructions with a loop, called from four closures; inlining it four times grows code and gives the loop no more facts than the table does.
- Unsigned or range-typed `Int` parameters in the language: changes the language and every signature for something the compiler can find.
- Rewrite the benchmark with `bit_and`: hides the gap in one program (the experiment is evidence only).

## Open questions

None for the language.
