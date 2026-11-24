# Linear-time owner state in elaborate and the verifier

## Summary

- Compile time is quadratic in the owners live at once in one function (#4020): `ms build` of a function with N live list locals, each captured by a closure and followed by a branch, takes about 4x per doubling of N.
- Stage 1 (landed with this file) stops `elaborate::merge` rebuilding equal states: 4.27G to 2.79G instructions at N = 960. The remaining quadratic cost is state copied between blocks, mostly in the verifier.
- Stages 2 to 4 built: a persistent set for the verifier's live owners, and a persistent position map for `elaborate`'s ordered state once the profile showed it matters. Decision requested: none.

## Status

Proposal, 2026-11-15, main at 4580c1dfa. Stages 1 to 4 implemented. Skeptical review: build a smaller version (the first draft's trie for `elaborate` was dropped: `elaborate` needs definition order, and per-path positions are not comparable across paths).

## Problem

Shape (generated; N repetitions of the first three lines in `fn main`): `xs{i}: List[Int] := [i, 2]`, `run(fn: sink(xs{i}.length()))`, `if opaque(i) > 1000000: sink(1)`.

| N | `ms build` before | after stage 1 | after stage 3 |
| --- | --- | --- | --- |
| 960 | 0.97 s | 0.70 s | 0.64 s |
| 1920 | 2.38 s | 1.68 s | 1.30 s |
| 3840 | 8.27 s | 4.83 s | 3.68 s |

After stage 3, N = 960 is 2.36G instructions (2.79G after stage 1, 4.27G before); `verify_module_with` fell from 17.6% to 1.7% of the run. After stage 4, 2.18G. After dirty-block `analyze`, entry equality by `same_entries` and an index of owners in a maybe state, 1.99G; wall time at 960 / 1920 / 3840 owners fell from 0.97 / 2.38 / 8.27 s to 0.62 / 1.27 / 2.61 s.

Per phase, inclusive instructions from N = 480 to 960 after stage 4 (a linear phase is 2.0x): `opt::optimize` 2.05x, `llvm::compile` 2.04x, `verify_module_with` 2.2x, `elaborate::run` 2.1x. `unwind::run` is not visible in the profile for this shape. Wall time is noisy on the shared machine (3840 owners: 2.8 to 3.7 s over runs); use instruction counts.

`valgrind --tool=callgrind`, release `ms build`, N = 960 against 480, inclusive Ir after stage 1 (4.0x or more is quadratic):

- `verify::check_ownership` clones its live `BTreeSet<u32>` into each block's entry state and per edge, and drops them: about 14% of the run (`verify_module_with` is 17.6% in total).
- `elaborate::State::push` copies the whole `Owners` when its `Rc` is shared with a block's stored entry state: 2,880 copies, 3.8%.
- `elaborate::merge`: 1.8% now (was 33%): one in-place equality scan per edge.
- The scans the reviewer named (`retain` at scope end, `maybe`/`ckeys`/`fparams`, the `exit` walk) do not appear in the profile for this shape. `elaborate::run` is 16% in total: `analyze` 5.8%, `apply` 4.5%, `push` 3.8%, `Em::block` 2.9%.
- Not yet measured: `unwind` (`coverable`, `hoist_loops`, `plan_flow`, Cranelift path) and `opt` (28% of the run, ratio unknown).

## Design

Rule: the verifier's live set is a persistent set, so an edge costs its changes, not its size.

- The verifier keys owners by `Value` (a dense index), never reads them in order, and requires exact equality at joins (`verify.rs`, the check after `entry_state`). A persistent set (32-way radix trie of bitmap words, `Rc` nodes, path copying) fits: `insert`, `remove`, `contains` in O(log32 N), clone is one `Rc` clone, equality skips `Rc`-equal subtrees.
- `elaborate::State` keeps definition order (it drives drop order and flag parameters) as a persistent map keyed by position, which only grows, plus a persistent value-to-position map; no `Rc<Owners>` copy on the first change in a block.
- No change to the elaboration rules, the `St` lattice or the facts the checker records.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `crates/ms-mir/src/persist.rs` (new) | `OwnerSet`, `PosMap` | unit tests against `BTreeSet` and `BTreeMap` models with random operations |
| `crates/ms-mir/src/verify.rs` | `check_ownership` live sets | existing verifier tests; N-doubling table |
| `crates/ms-mir/src/elaborate.rs` | `merge` equality; `State` on `PosMap`; scope-end removal; flag-parameter candidates | ownership conformance, e2e corpus with leak counting |
| `tools/scaling` shapes `test_owners`, `test_branches` | three sizes, once the ratio is under 2.5x; the added time is stated in that PR against the 10-minute budget | the gate |

## Alternatives

- Do nothing: only generated code with thousands of live owners is slow (400 compile in 0.4 s), but each doubling costs about 3x even after stage 1. Valid if no real program hits it; the issue's trigger is machine-generated.
- Stage 1 plus avoiding the `push` copy only: about 4% more, still quadratic. Fallback if the persistent set is rejected.
- A persistent map for `elaborate` too: first rejected for needing definition order and positions that agree across paths. Built after the profile showed it matters: positions only grow, iteration is by position, and joins compare by tree identity, falling back to the owner sequence.
- `im` or `rpds`: a new dependency, which needs the owner's approval.

## Stages

1. `merge` returns the old state when the new one is equal (landed with this file).
2. `persist.rs` (`OwnerSet`) with its model tests (landed). Check: `cargo test -p ms-mir`.
3. The verifier on `OwnerSet` (landed). Check: N-doubling table and a profile with no `BTreeSet` clones.
4. `elaborate`'s `State` on two `PosMap`s (position to owner, value to position), a scope end removing its own owners, and block flag parameters looking only at owners that can have one (landed, replacing "avoid the push copy": the copy was the symptom). Check: same table, e2e corpus with leak counting (661/661).
5. Profile `unwind` and `opt` (done above: both linear for the `main` shape). `elaborate::run` is now 2.1x.
6. `unwind` in a `test` (#4190): the same body in `ms test` took 9.2 s and 1.4 GB at 3000 owners and was OOM-killed at 10000 (13.6 GB), 60% of it in `unwind::run`. Events and windows held a full owner `Vec` per faulting instruction, and `plan_flow` cloned the cleanup stack three times per block and pass. Now owner sets are `OwnerSet`s (shared trees, `diff` skips what two sets share) and a cleanup stack is a node of a shared-prefix tree (`Stacks`): copying is free, a common prefix is the common ancestor, and a cut is found from the dead owners through a persistent owner-to-depth map. 3000 owners: 3.3 s and 112 MB; 10000 owners: 311 MB. Check: e2e corpus with leak counting (661/661), `registers_each_of_many_live_owners_once`.

What stays superlinear in a test build is not ours: Cranelift's register allocator takes 3.3x per doubling (0.19, 0.62, 2.1 s at 1000, 2000, 4000 owners), and #4191 (a frame over a 512 KiB task slot) fails a test at about 5000 owners. The gate shapes `test_owners` and `test_branches` stay at one size until both are addressed.

## Open questions

None: no language or user-visible change.
