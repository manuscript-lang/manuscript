# List-chain fusion across fault exits

* Status: **Proposed** (2026-11-25, main at 58d33fbe)
* Authors: [Claude](https://github.com/chinmaymk)
* Implementation: not yet implemented
* Issue: #7039

## Summary

- Problem: `opt_fuse` never matches today, so `map.filter.sum` builds two temporary lists (24 instructions per element, Rust 8).
- Change: let both loops leave by fault exits, keep the fused loop's cleanup complete, and assert in a test that chains fuse.
- Decision requested: none for the language; this changes only generated code.

## Motivation

- `closures_20M` is 1.36x checked Rust ([kernels README](../../bench/perf/kernels/README.md), 2026-11-23). Measured with callgrind on the chain alone (20,000 rounds of 1000 elements): 479M instructions on `main`.
- The wiki records 9.1 ms fused against 37 ms staged ([wiki page](../wiki/benchmarks-and-performance/a-list-built-and-read-once-never-exists.md)); `ms emit --opt` of the same chain on `main` shows two `list.push` loops, so the pass is silent.
- `e2e/accept/list-chain-fusion` checks only results, so the regression went unseen.

## Detailed design

A traced `match` shows why each reader header fails (`opt_fuse.c`):

1. `reader_body` rejects a body that reaches `ret`; every checked operation has a `fault.site` edge to a cleanup block that returns through one shared exit.
2. `reader_uses` allows one `drop` of the list; each fault exit drops it again.
3. `builder_slot` allows only the push triple, the initial put and the final take; each builder fault exit does `take S; drop`.
4. The entry block must be `list.len; br R`; a `msrt_unwinding` test splits it where an inlined callee's fault edge rejoins the caller's test.

The design changes the matcher, not the rewrite's idea:

- **Exit edges.** A loop's body is the blocks reachable from its first block that can reach its header. An edge leaving that set is an exit edge; its target is not touched. Reject when a block reachable from a reader exit edge uses the counter or an accumulator (the later `loaded` value would not dominate it).
- **Drops of the vanishing list.** `reader_uses` counts all `drop`s of the list; `mark_dead` already deletes every one of them.
- **Upstream builder exits.** A `take S` outside the loop whose only use is one `drop` is deleted with its drop (the list never exists). Any other touch of `S` still rejects.
- **Downstream cleanup.** The hoisted setup makes the next stage's list before the loop. Each builder-loop exit edge gets a new block that does `take S2; drop` of that slot and then branches to the old target with the same arguments; without it a fault leaks the partial list. The reader-body exits already clean it.
- **Entry shape.** Run `unwind thread` before `fuse` so the entry block holds only the setup.
- **Order of faults** keeps the owner's 2026-11-23 rule: the later loop's fault may be reported when both would fault.

## Fit with the language

- **Memory model:** no change; the list had one owner and now never exists.
- **Platforms:** target-independent MIR pass.

## Measured benefit

Chain alone, 479M instructions today. Target: within 1.3x of a hand-fused loop (about 12 per element). The kernel `closures_20M` is re-run against the 2026-11-23 table.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `src/compiler/opt/opt_fuse.c` | matcher and rewrite above | new MIR-level fixture counting `list.push` in `ms emit --opt` for a three-stage chain; `list-chain-fusion` results |
| `src/compiler/opt/opt_pipeline.c` | order of `unwind thread` and `fuse` | corpus |

## Alternatives considered

- Do nothing: leaves the widest list-pipeline gap and a pass that silently never runs.
- Delete the pass: forbids the one general fix for chained stages; hand-fused loops are what Rust gets from lazy iterators.
- Lazy iterators in the language: a language change, far larger, and still needs fault-safe cleanup.
- Remove fault exits from loops (return an error value): costs a branch per checked operation in every loop.

## Review

Self-review (no other model, per project rule): the do-nothing case is weakest where the chain is rare, but chained `map`/`filter`/`sum` is the common iterator style, and the pass costs no new construct. Open risk: the downstream cleanup blocks; the fixture must fault in the builder loop and check no leak with the sanitize preset.
