# MIR ownership passes scale with the function, not the candidate

## Summary

- Problem: Release `ms build` of one long `main` is quadratic (and in `optparam`, cubic): N=400 takes 5.9s, N=800 takes 19.4s; Debug and `ms check` stay fast.
- Change: make `lastuse::candidate` and `optparam` cost proportional to the region they touch. No new IR, pass, flag, or language change.
- Cost: two local rewrites inside existing passes (~150 lines touched), no pipeline change.
- Decision requested: approve after skeptical review (AGENTS.md); no user-visible behavior changes.

## Status

- Proposal, 2026-10-28, checked against main `3cbaceb0`.
- Direction: issue #1767 ("Compile time grows steeply with statement count"); AGENTS.md asks for a proposal before restructuring.
- Skeptical review: pending.

## Problem

- Repro (measured, Linux, release `ms`): one `main` with N lines `check(i, "idx", show("abe{i}".index_of("b")), "none")`; `ms build` Release: N=400 5.9s, N=800 19.4s (3.3x for 2x). `--build-type Debug` 0.4s at N=800.
- Profile on #1767 (gdb sampling, N=800): about 12s of 17.8s is in MIR passes: `lastuse::candidate` 6/14 samples, `optparam::split_one`/`apply` 7/14, one each `simplify::branches`, `copyelim::borrow_str_phis`.
- Generated tests and tables are plausible agent output; one function with thousands of statements must not take minutes.
- Non-goals: changing what either pass optimizes; touching LLVM/Cranelift stages (`opt` 3.5s and `llc` 2.4s at N=800 are linear in IR size).

### Causes (verified in source)

- `optparam::split_one` (`opt/optparam.rs:53`) scans the whole function for defs and use counts, then for each eligible-looking block parameter scans every block's terminator (`:82`), and returns after splitting one parameter; `run` loops until none remain. `apply` rebuilds the defs map and rewrites every block per split. Cost: splits x (params x blocks + insts) = cubic when each call site adds a merge parameter.
- `lastuse::candidate` (`opt/lastuse.rs`) allocates about ten vectors of `nb` blocks per candidate and iterates liveness and ownership dataflow over all blocks, though only blocks forward-reachable from the definition up to its original drop matter. It also recomputes `succs` for all blocks, rescans `ix.uses[v]` once per block in `consume_at`, and loops all `nb` blocks per family member in the `pending_drops` setup. Cost: candidates x blocks, with extra factors.

## Design

### optparam: batch per sweep

- One analysis sweep builds defs, other-use counts, and the incoming edges per block (`preds[block] -> [(src, target)]`).
- Every eligible parameter found in the sweep is split in one rewrite sweep. Within a block, split higher `k` first so lower indices stay valid.
- `run` keeps the outer `while` as a fixpoint check; the second sweep normally finds nothing. Splitting never changes another parameter's incoming constructors (readers are removed, constructors stay), so batching equals the sequential result.
- Cost: O(insts + edges) per sweep.

### lastuse: restrict each candidate to its region

- Region F(v): blocks forward-reachable from the definition block, not expanding past a block that holds an original drop of `v` (`drop_at` set; its `live_out` is already false there). Exact, not a heuristic: `live_out` reads only successors of non-cut blocks, and `owned_*` can only be true inside F.
- Index all per-candidate state by position in F (a reusable scratch with a block-to-local map) instead of by block id; compute `succs`/`preds` only for blocks in F.
- `consume_at`: one pass over `ix.uses[v]` builds block -> earliest owning consumption.
- Pending drops: keep a per-value list of blocks that hold a pending drop of it (`Index.pending_blocks`), replacing the loop over all blocks per family member.
- Results must be identical: same drops moved to the same positions; the existing `crates/ms-mir/tests/opt_lastuse.rs` stays unchanged and passes.
- Cost: O(|F| + family uses) per candidate. A candidate whose drop is near its definition is O(1)-ish.

### Residual risk: long-lived candidates

- A value defined early and dropped at the function end has F = the rest of the function, so a function with many such values stays quadratic. Not seen in the repro (temporaries drop locally). If measurement shows it, a follow-up is a single backward sweep shared across candidates; out of scope until measured.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `crates/ms-mir/src/opt/optparam.rs` | batch split | existing MIR tests + conformance; new unit test with many merges |
| `crates/ms-mir/src/opt/lastuse.rs` | region-restricted candidate | `tests/opt_lastuse.rs` unchanged; equivalence check on corpus (below) |
| `crates/ms-mir/src/opt/mod.rs` | unchanged (pipeline order same) | none |
| parser, checker, lowering, codegen, `ms-rt`, stdlib, tooling, docs | unchanged | none |

## Alternatives

- Do nothing: 19s at N=800 and 3 minutes at N=3080 (#1767); agents hit this with generated tests. Rejected.
- Skip `lastuse`/`optparam` above an instruction threshold (as Level::None does for `lastuse`): trades speed for runtime memory and code quality exactly on large generated functions; hides the asymptotics. Rejected as the fix.
- Rewrite `lastuse` as one global backward/forward dataflow for all candidates (bitsets): larger change to a subtle pass, needs its own proof. Held as the follow-up if long-lived candidates dominate.
- Split large functions in lowering: changes semantics-adjacent behavior and stack traces. Rejected.

## Staging and verification

1. Add a scaling test: time-independent proxy, e.g. a MIR-level unit test asserting the pass makes work-counter bounds (or a perf-stage example run in `bench/perf`) at N=200/400/800; record before/after numbers in this file.
2. `optparam` batching. Check: `cargo nextest run -p ms-mir`, `make conform`, re-measure.
3. `lastuse` region restriction. Check: as above, plus an equivalence run: print optimized MIR for the conformance corpus before and after and diff (must be identical).
4. Go/no-go: stop and revisit if the MIR diff is non-empty or N=800 does not drop below 2x the N=400 time.
5. `make verify` on each stage; Linux, macOS, Windows CI at parity, no test gated.

## Open questions

- None; no language or user-visible behavior changes.
