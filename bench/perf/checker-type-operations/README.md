# Checker substitution investigation — 2026-11-10

**A real exponential checker workload was reproduced; no fix qualified.**
[Issue #3487](https://github.com/manuscript-lang/manuscript/issues/3487) remains
open. Five experimental implementations were rejected. Production code and tests
were restored; the patches here are evidence, not proposed changes. No fix PR,
merge, or performance improvement shipped.

Evidence-only validation: all four Python scripts compile; `make repo-check`
and `git diff --cached --check` pass after restoring production code and tests.
These checks do not qualify
any rejected implementation for merge.

## Baseline and setup

Measured base: `d1ea6ce161ed9e5bd1af5c3b4edd8ca0b8f4b251`, then-current main.
Final live-main check found `ae87acedab5641ffac4179b17e3e0dc442fcca0e`;
the four assigned checker files and build settings are unchanged. Later JWT/math
changes were not benchmarked. Open PRs #3488, #3493, #3495, #3496 and #3497 do
not implement this substitution repair. Initially open #3481 and #3351 merged.

Linux 6.18.57 x86_64, AMD EPYC 9V74 shared VM, five visible CPUs, CPU0 affinity.
The owner's continuation authorized installing official Rust into permitted
workspace directories. `https://sh.rustup.rs` installed the repository-pinned
Rust 1.99.1 into `/workspace/checker-perf-tools/{cargo,rustup}`. No protected
toolchain/cache was changed. Actual compiler: rustc 1.99.1
`58cf8f9c35b355199727627d07ae34a4e2846d67`, LLVM 23.1.1; cargo 1.99.1
`5f94df478`. All builds use repository release settings: optimization level 3,
debug=1, panic=abort, force-frame-pointers=yes. Rust tests use their normal
unwind test profile; benchmark libraries use the production abort profile.

Fresh `make build` and `cargo test --release --locked -p ms-check` succeeded:
134 unit + 91 integration tests, no failures. See [logs](logs/).
The latest all-suite [baseline](../baseline-2026-10-28.md),
[November 9 report](../perf-bash-2026-11-09.md), and
[compile-time results](../../compile-time/README.md) were consulted; their
different-machine timings are not before/after comparisons.

## Demonstrated workload

`generate.py` creates a phantom `Pair[A,B]` with one Int field. Repeated calls
to `double[T]` produce `Pair[T,T]`, sharing the same concrete type subtree.
Calling `with_second[C]` on that receiver triggers substitution through every
path of the shared graph. Source size and represented graph grow linearly.
Matching the same value and constructing a callback are neighboring controls.

Production `ms check --json` includes complete process startup, stdlib loading,
checking and JSON output. One warmup followed by seven CPU-pinned trials per
case, seeded shuffled order, no concurrent local build/test:

| Depth | Method median | Match control | Callback control |
| --- | ---: | ---: | ---: |
| 20 | 74.965 ms | 55.291 ms | 55.619 ms |
| 24 | 328.640 ms | 58.470 ms | 59.236 ms |
| 28 | 4255.220 ms | 62.692 ms | 59.293 ms |

At depth28 the method's median CPU time is 4243.970 ms and minor faults 4796,
versus 4794 for both controls. All 248 processes returned exactly the expected
empty diagnostics, exit0 and empty stderr. Ordinary concrete/generic function
controls cover 1/16/250/500/1000 declarations. Full inputs, commands, output,
binary/input hashes, machine info and resource samples are in
[baseline-2026-11-10.json](baseline-2026-11-10.json).

This is a checker-process result. No workload executable was linked or run, and
no native application throughput improvement is claimed.

## Rejected experiments

Each patch applies to the measured base. Patches were regenerated with zero
context (`git apply --unidiff-zero`) and
checked for applicability. Only trailing blank log lines were removed; raw
timing/output JSON is unchanged. Scope stayed in `types::sub/sub_walk`;
bindings for arbitrary type IDs and independent mutable variable snapshots must
be preserved. The final two variants skip only an adjacent identical pointer
after its predecessor was proved unchanged; the first changed child still uses
the original suffix mapper. This does not bound nonadjacent sharing.

| Candidate | Evidence | Reason rejected |
| --- | --- | --- |
| Root negative preflight | `rejected-root-preflight.patch`, `preflight-smoke.json` | Mixed changed/concrete roots still traverse the expensive subtree; depth28 remained 4.089 s in a smoke trial. No repeated win claimed. |
| Memoize completed unchanged nodes after 64 visits | `rejected-all-nodes.patch`, `unchanged-micro.json` | Unshared chains64/128/256 slowed roughly 7–10×; small concrete signatures also slowed. |
| Restrict memoization to multiply owned nodes; inline leaf dispatch | `rejected-shared-only.patch`, `shared-only-micro.json`, `shared-only-source.json` | Unshared-chain paired medians slowed 36–55%, every one of seven pairs at each depth. |
| Adjacent unchanged prefix, previous child by index | `rejected-adjacent-index.patch`, `adjacent-micro.json` | Mixed Int/String/Bool parameter lists slowed materially, increasing with width. |
| Adjacent unchanged prefix, previous pointer in local variable | `rejected-adjacent-pointer.patch`, `adjacent-pointer-micro.json` | Mixed signatures improved, but unique chains and Fibonacci sharing regressed. |

The shared-only candidate's full production run has 52 sources, nine paired
rounds plus warmups: **1040 exact validations passed**, including four rejected
sources whose diagnostic bytes and exit1 were preserved. Method depth28 changed
from 4325.000 to 63.244 ms. Ordinary concrete1000 changed 74.536 to 77.060 ms
(paired median 1.056×); generic1000 89.520 to 88.413 ms (paired median 1.009×).
These are different trials from the initial baseline. This dramatic target win
does not qualify the candidate because neighboring operation controls regressed.

Final pointer candidate, nine paired rounds, median of candidate/base ratios:

| Control | Ratio | Slower pairs |
| --- | ---: | ---: |
| Unique chain4 | 1.112 | 8/9 |
| Unique chain64 | 1.138 | 8/9 |
| Unique chain128 | 1.142 | 7/9 |
| Unique chain256 | 1.252 | 8/9 |
| Fibonacci16 | 1.165 | 8/9 |

Full case summaries, including favorable and unfavorable controls, are in
[summary.txt](summary.txt), generated by `python3 summarize.py`. Operation
timings use the actual release ms-check library, not a reimplemented algorithm.
Setup and structural/pointer assertions are outside timing; output destruction
is timed. Each process performs ten warmups. Trials alternate binary order and
shuffle cases deterministically. Shared cases use 10 iterations, unique 20,000,
signature cases 100,000, Fibonacci 100. The earlier seven-round micro runs have
22 cases; final nine-round runs add mixed signatures and Fibonacci for 29 cases.

## Reproduction

Keep toolchain/cache state in an authorized workspace. The session wrapper set
`CARGO_HOME=/workspace/checker-perf-tools/cargo`,
`RUSTUP_HOME=/workspace/checker-perf-tools/rustup` and prepended `$CARGO_HOME/bin`.
Build each variant independently at the base plus its retained patch. Run this
initial block from a pristine checkout of the measured base, before applying a
candidate:

```sh
make build
cargo test --release --locked -p ms-check
mkdir -p .artifacts/checker-type-operations/base
cp target/release/ms .artifacts/checker-type-operations/base/ms
python3 bench/perf/checker-type-operations/generate.py .artifacts/checker-type-operations/inputs
python3 bench/perf/checker-type-operations/measure.py --binary base=.artifacts/checker-type-operations/base/ms --inputs .artifacts/checker-type-operations/inputs --output fresh-baseline.json --samples 7
```

The expanded generator now produces 52 cases; initial baseline used 31 before
unique-method/callback-method/rejected controls were added. Original inputs
remain embedded in each raw result. Copy each just-built CLI before changing
source. Full comparison commands use two `--binary label=path` arguments;
`shared-only-source.json` used `base` and `candidate`, `--samples 9`.

Micro harness compilation was identical on both sides, linking separately built
release libraries (no LTO or new dependencies):

```sh
rustc --edition=2024 -O -C panic=abort -C force-frame-pointers=yes -C debuginfo=1 bench/perf/checker-type-operations/substitution.rs --extern ms_check=/workspace/checker-perf-base/target/release/libms_check.rlib -L dependency=/workspace/checker-perf-base/target/release/deps -o .artifacts/checker-type-operations/base/substitution-expanded
rustc --edition=2024 -O -C panic=abort -C force-frame-pointers=yes -C debuginfo=1 bench/perf/checker-type-operations/substitution.rs --extern ms_check=target/release/deps/libms_check-a9fc9d9f25cc6466.rlib -L dependency=target/release/deps -o .artifacts/checker-type-operations/adjacent-pointer/substitution
python3 bench/perf/checker-type-operations/measure-substitution.py .artifacts/checker-type-operations/base/substitution-expanded .artifacts/checker-type-operations/adjacent-pointer/substitution fresh-micro.json --samples 9
```

Baseline worktree is detached at d1ea6ce; its library was built with
`cargo build --release --locked -p ms-check`. Candidate builds used that command
or `make build`; the deps artifact above is the production panic-abort library,
not the separately hashed unwind test library. A future build may use another
artifact hash; use its actual release artifact. Raw JSON identifies binaries by
SHA256. Earlier harness versions lack only the subsequently added case arms.

## Review, checks and limits

Independent Astra/high reviewer `review_substitution` inspected snapshot/key
correctness and raw measurements without concurrent builds. It found no semantic
blocker in pointer-prefix reuse, independently verified all 522 final micro trials
and 1040 source outputs, and recommended rejecting the final candidate because
the controls regress. Seven focused substitution tests passed on the memoized
and adjacent-index experiments. Added controls cover late arbitrary binding keys,
callable metadata, root precedence, independent repeated snapshots and mutation
between queries. The three added tests, plus four existing tests, are retained in
`rejected-shared-only.patch` and `rejected-adjacent-pointer.patch`; the all-nodes
and adjacent-index patches contain implementation changes only. Replaying one
of those implementation-only patches needs the test-file hunk from either full
patch to reproduce the seven-test run.

The final pointer variant compiled and passed all harness assertions, but its
full checker/source suites were not run after micro controls rejected it. No
workspace Clippy/nextest, native conformance/e2e, macOS/Windows or exact-head CI
was run for a proposed fix: no implementation qualified for publication. No
failed check was ignored or disabled. No perf/valgrind instruction counts or A/A
noise run are available. Shared-VM timing noise limits precision, particularly
small differences; repeated sizable regressions support conservative rejection,
not a universal quantified slowdown claim. No broad representation redesign
was attempted. A future repair needs a new reviewed design and all qualification
gates; issue #3487 is still unresolved.
