# Linear-time owner state in elaborate and the verifier

## Summary

- Compile time is quadratic in the owners live at once in one function (#4020): `ms build` of a function with N live list locals, each captured by a closure and followed by a branch, takes about 4x per doubling of N.
- Stage 1 (landed with this file) stops `elaborate::merge` rebuilding equal states: 4.27G to 2.79G instructions at N = 960. The remaining quadratic cost is state copied between blocks, mostly in the verifier.
- Decision requested: build a persistent, order-free set for the verifier's live owners next; leave `elaborate`'s ordered state alone unless a later profile shows it matters.

## Status

Proposal, 2026-11-15, main at 4580c1dfa. Stages 1 to 3 implemented. Skeptical review: build a smaller version (the first draft's trie for `elaborate` was dropped: `elaborate` needs definition order, and per-path positions are not comparable across paths).

## Problem

Shape (generated; N repetitions of the first three lines in `fn main`): `xs{i}: List[Int] := [i, 2]`, `run(fn: sink(xs{i}.length()))`, `if opaque(i) > 1000000: sink(1)`.

| N | `ms build` before | after stage 1 | after stage 3 |
| --- | --- | --- | --- |
| 960 | 0.97 s | 0.70 s | 0.64 s |
| 1920 | 2.38 s | 1.68 s | 1.30 s |
| 3840 | 8.27 s | 4.83 s | 3.68 s |

After stage 3, N = 960 is 2.36G instructions (2.79G after stage 1, 4.27G before); `verify_module_with` fell from 17.6% to 1.7% of the run. Doubling still costs 2.0x then 2.8x: the rest is in `elaborate`, `unwind` and `opt`.

`valgrind --tool=callgrind`, release `ms build`, N = 960 against 480, inclusive Ir after stage 1 (4.0x or more is quadratic):

- `verify::check_ownership` clones its live `BTreeSet<u32>` into each block's entry state and per edge, and drops them: about 14% of the run (`verify_module_with` is 17.6% in total).
- `elaborate::State::push` copies the whole `Owners` when its `Rc` is shared with a block's stored entry state: 2,880 copies, 3.8%.
- `elaborate::merge`: 1.8% now (was 33%): one in-place equality scan per edge.
- The scans the reviewer named (`retain` at scope end, `maybe`/`ckeys`/`fparams`, the `exit` walk) do not appear in the profile for this shape. `elaborate::run` is 16% in total: `analyze` 5.8%, `apply` 4.5%, `push` 3.8%, `Em::block` 2.9%.
- Not yet measured: `unwind` (`coverable`, `hoist_loops`, `plan_flow`, Cranelift path) and `opt` (28% of the run, ratio unknown).

## Design

Rule: the verifier's live set is a persistent set, so an edge costs its changes, not its size.

- The verifier keys owners by `Value` (a dense index), never reads them in order, and requires exact equality at joins (`verify.rs`, the check after `entry_state`). A persistent set (32-way radix trie of bitmap words, `Rc` nodes, path copying) fits: `insert`, `remove`, `contains` in O(log32 N), clone is one `Rc` clone, equality skips `Rc`-equal subtrees.
- `elaborate::Owners` keeps its ordered `BTreeMap` (definition order drives drop order and flag parameters). It stops copying on push by not keeping a second `Rc` of the working state in the block entry table: move it in when the block has one successor, clone it otherwise.
- No change to the elaboration rules, the `St` lattice or the facts the checker records.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `crates/ms-mir/src/persist.rs` (new) | persistent set | unit tests against a `BTreeSet` model with random operations |
| `crates/ms-mir/src/verify.rs` | `check_ownership` live sets | existing verifier tests; N-doubling table |
| `crates/ms-mir/src/elaborate.rs` | `merge` equality (done); entry-table ownership | ownership conformance |
| `tools/scaling` shapes `test_owners`, `test_branches` | three sizes, once the ratio is under 2.5x; the added time is stated in that PR against the 10-minute budget | the gate |

## Alternatives

- Do nothing: only generated code with thousands of live owners is slow (400 compile in 0.4 s), but each doubling costs about 3x even after stage 1. Valid if no real program hits it; the issue's trigger is machine-generated.
- Stage 1 plus avoiding the `push` copy only: about 4% more, still quadratic. Fallback if the persistent set is rejected.
- A persistent map for `elaborate` too: rejected, since it needs definition order and positions that agree across paths.
- `im` or `rpds`: a new dependency, which needs the owner's approval.

## Stages

1. `merge` returns the old state when the new one is equal (landed with this file).
2. `persist.rs` (`OwnerSet`) with its model tests (landed). Check: `cargo test -p ms-mir`.
3. The verifier on `OwnerSet` (landed). Check: N-doubling table and a profile with no `BTreeSet` clones.
4. Avoid the `push` copy in `elaborate`. Check: same table.
5. Profile `unwind` and `opt` at N = 960 and 1920; extend this file with what is quadratic there, then raise the gate shapes.

## Open questions

None: no language or user-visible change.
