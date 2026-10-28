# SSA builder: long-lived variables across many joins

## Summary

- Problem: `ms_mir::builder::read_var` is quadratic when many variables stay live across many join blocks; it also hits Debug (`ms build --build-type Debug`: N=400 0.75s, N=800 2.8s, N=1600 12.7s).
- Change: a fast path in `read_var` for variables with a single definition whose region is fully built, so a read does not walk and phi-test every join back to the definition.
- Cost: bookkeeping per block and per variable inside `builder.rs`; no IR, language, or pass change.
- Decision requested: approve the design (or the do-nothing alternative) after skeptical review.

## Status

- Proposal, 2026-10-28, checked against main after #1854.
- Direction: issue #1856; AGENTS.md requires a proposal before restructuring.
- Skeptical review: pending.

## Problem

- Repro (`mir-scaling-review/gen-longlived-repro.sh N long`): N `let k_i = "key{i}".upper()`, then N `if "abe{i}".upper() != "ABE{i}": bad += 1`, then N `bad += k_i.length()`. Measured Debug 0.75s, 2.8s, 12.7s at N=400, 800, 1600 (about 4.5x per doubling).
- Samples: hash operations on `defs: HashMap<(Var, Block), Value>` and `forward` inside `read_var`.
- Cause (verified, `builder.rs` `read_var`): the lazy algorithm materializes one `(var, block)` entry per variable per join between the definition and a read, adds a block parameter, then removes it as trivial. N variables x N joins = N² entries (2.5M at N=1600).
- Non-goals: the Release-only costs (fixed in #1854, #1858 for the optimizer and LLVM).

## Design

- Per variable, count `def_var` calls and remember the single defining value while the count is 1.
- A block is *closed* when it is sealed and every predecessor is closed (computed once when it is sealed, with loop back edges handled by treating blocks of the same unsealed cycle as open). Closed means no definition can still appear on any path into it.
- `read_var(v, b)`: if `b` is closed and `v` has exactly one definition, return it without creating parameters. Otherwise the existing algorithm runs unchanged.
- Soundness argument: lowering only reads a variable where it is defined on every path (the existing `panic!("used before it is defined on every path")` guards this); with one definition in total, that definition is the value on every path.
- A variable reassigned later (`bad += 1`) has two definitions and takes the existing path, whose cost is one walk per variable.
- Result must be identical to the existing algorithm's output for the programs it handles; the fast path may only remove parameters the slow path would also have removed as trivial.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `crates/ms-mir/src/builder.rs` | def counts, closed-block tracking, fast path in `read_var` | builder unit tests; MIR text equal to before on the conformance corpus |
| lowering, passes, codegen, runtime, tooling, docs | unchanged | `make conform`, `make e2e` |

## Alternatives

- Do nothing: Debug N=1600 takes 12.7s; generated functions with thousands of long-lived locals are rare but plausible agent output. Smallest cost: nothing changes.
- Constant-factor work (cheaper maps, avoiding `preds.clone()`): measured hash cost dominates; still N², gains below 2x.
- Compute dominators and place phis at dominance frontiers (classic Cytron SSA) after building: asymptotically better but rewrites the builder and every lowering call site's use of `use_var`/`def_var`; much larger.
- Incrementally maintained immediate dominators and "jump to the nearest dominating definition" in `read_var`: handles reassigned variables too; complicated by loops (back edges change dominance until sealed). Held as the follow-up if single-definition variables turn out not to be the common case.

## Staging and verification

1. Add a builder-level scaling test (N long-lived variables across N joins) that counts `defs` entries, not time, so it is stable on every platform.
2. Implement the fast path; check MIR text equality over the conformance corpus before and after (any difference must be only renumbering), `make conform`, `make e2e`.
3. Gate: Debug N=1600 under 3x the N=800 time; stop and use the dominator alternative if reads of reassigned variables dominate instead.

## Open questions

- None; no language or user-visible behavior change.
