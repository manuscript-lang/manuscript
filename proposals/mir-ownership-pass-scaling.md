# MIR ownership passes scale with the function, not the candidate

## Summary

- Problem: Release `ms build` of one long `main` is quadratic (and in `optparam`, cubic): N=400 takes 5.9s, N=800 takes 19.4s; Debug and `ms check` stay fast.
- Change: make `lastuse::candidate` and `optparam` cost proportional to the region they touch. No new IR, pass, flag, or language change.
- Cost: two local rewrites inside existing passes (~150 lines touched), no pipeline change.
- Decision requested: approve after skeptical review (AGENTS.md); no user-visible behavior changes.

## Status

- Proposal, 2026-10-28, checked against main `3cbaceb0`.
- Direction: issue #1767 ("Compile time grows steeply with statement count"); AGENTS.md asks for a proposal before restructuring.
- Skeptical review (separate thread, 2026-10-28): optparam evidence solid; the original repro was not self-contained and the lastuse profile did not reproduce at N=800 on the reviewer's machine; "cubic" unsupported (~N^1.8); "O(|F| + uses)" false while pending drops are scanned per block; empty-MIR-diff gate too strict (value ids differ); go/no-go too weak.
- Outcome: landed optparam first. After it, lastuse became the top MIR hotspot on this machine (6 of 8 samples at N=800), so the region restriction proceeds, with `Index::apply` and the per-value pending-block index included. Gates revised below. Long-lived values and `builder::read_var` are out of scope (separate issue).

## Problem

- Repro (measured, Linux, release `ms` at `3cbaceb0`): the generator in the appendix; `ms build` Release: N=400 5.9s, N=800 19.4s (3.3x for 2x). `--build-type Debug` 0.4s at N=800.
- Profile on #1767 (gdb sampling, N=800): about 12s of 17.8s is in MIR passes: `lastuse::candidate` 6/14 samples, `optparam::split_one`/`apply` 7/14, one each `simplify::branches`, `copyelim::borrow_str_phis`.
- Generated tests and tables are plausible agent output; one function with thousands of statements must not take minutes.
- Non-goals: changing what either pass optimizes; touching LLVM/Cranelift stages (`opt` 3.5s and `llc` 2.4s at N=800 are linear in IR size).

### Causes (verified in source)

- `optparam::split_one` (`opt/optparam.rs:53`) scans the whole function for defs and use counts, then for each eligible-looking block parameter scans every block's terminator (`:82`), and returns after splitting one parameter; `run` loops until none remain. `apply` rebuilds the defs map and rewrites every block per split. Cost: splits x (params x blocks + insts); measured growth ~N^1.8 (reviewer), so not cubic in practice.
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
- `Index::apply` groups pending drops by anchor once per block (was insts x pending).
- Cost: O(|F| + family uses) per candidate, plus the pending drops of its own block. A candidate whose drop is near its definition is small.

### Residual risk: long-lived candidates

- A value defined early and used at the function end has F = the rest of the function, so many such values stay quadratic (reviewer: N lets up front, N ifs, use at end: Release 6.2s at N=800, 24s at 1600; part is `builder::read_var`/`add_phi_operands`, which also hits Debug). Out of scope here; separate issue.

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

1. optparam batching (landed first). Check: `cargo test -p ms-mir`, `make conform`, re-measure.
2. lastuse region restriction. Same checks. Equivalence: the existing `tests/opt_lastuse.rs` unchanged, plus the conformance corpus; MIR text may differ only by renumbering, so no byte diff gate.
3. Gates: MIR optimizer time at N=1600 under 2s (measured 1.3s after both); `make verify` and CI on Linux, macOS, Windows; no test gated.
4. Residual: end-to-end Release still grows superlinearly after the MIR fixes (N=800 8.8s, 1600 25s, 3200 95s) because LLVM `opt`/`llc` dominate (`llvm_obj::run`); a separate follow-up.

## Appendix: repro generator

```python
import sys
n = int(sys.argv[1])
print('''from "@std/io/io.ms" import stdout

def show(o: Optional[Int]) -> String:
    if let v = o:
        return f"{v}"
    return "none"

def check(i: Int, name: String, got: String, want: String) -> Unit:
    if got != want:
        stdout().write(f"FAIL {i} {name}\\n").get()

export def main() -> Int:''')
for i in range(n):
    print(f'    check({i}, "idx", show("abe{i}".index_of("b")), "none")')
print('    return 0')
```

## Open questions

- None; no language or user-visible behavior changes.
