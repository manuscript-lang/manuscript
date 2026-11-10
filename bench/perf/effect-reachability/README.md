# Effect reachability investigation, 2026-11-10

Status: production baseline reproduced and a candidate implemented. Release
paired measurements, repeated controls and focused correctness checks pass; final
hosted CI remains pending. No issue, PR, or merge yet.

Initial baseline: `d1ea6ce161ed9e5bd1af5c3b4edd8ca0b8f4b251`. Final measurements
use main `ae87acedab5641ffac4179b17e3e0dc442fcca0e`.
The latest dated all-suite baseline is [2026-10-28](../baseline-2026-10-28.md);
it does not measure effect analysis. The [2026-11-09 perf bash](../perf-bash-2026-11-09.md)
also has no matching effect-analysis measurement. Cross-machine numbers cannot
qualify this candidate.

## Candidate and source evidence

On original baseline `d1ea6ce16`, `crates/ms-check/src/effect_reach.rs:170` calls `path_to` separately for each
unpermitted effect. Each call allocates its own parent map and queue (198–199),
collects and sorts outgoing eligible edges (201–208), and checks for a declaring
callee only after collection (214).

Consider N roots that each call a shared hub. The hub calls N distinct leaves,
and every leaf calls one sink declaring `probe.io`. Each root's search scans and
enqueues all N hub edges before the first leaf reaches the sink. Repeating that
for N roots requires at least N² edge visits, although the graph has O(N)
nodes/edges and the output has O(N) path labels. Unique numbered identifiers
make asymptotic source/output bytes O(N log N). Root paths contain just four
labels. This is separate from the already-worklisted propagation loops in
`effects.rs` and `effect_reach.rs`.

The production baseline now reproduces this cost (results below). A deep chain
alone is a poor discriminator: its complete diagnostic paths already have
quadratic total length.

## Inputs and intended validation

The driver emits the wide shared graph and neighboring controls:
`allowed` permits the effect at file scope, `pure` omits the declaration,
and `direct` makes roots call the sink directly while retaining the hub and leaves.
`sparse` has one direct violation amid a permitted wide graph; `many` has one
direct violation per distinct effect; `cyclic` has disjoint declaring-start cycles.
The canonical Manuscript driver below generates and checks these inputs.
Historical exploratory scripts are preserved as text in `exploratory/` solely
to explain the original raw command records.

Build current main with
`make build`, then retain repeated `target/release/ms check` and
`target/release/ms lint --json` outputs, timings, instruction/page-fault counts,
and complete command/build metadata for these inputs. Use the same machine and
settings for any later candidate; alternate before/after trials and include
ordinary real-project controls. Time uncached end-to-end Release builds separately
and run their native outputs. The generated main is intended to return status 0
with empty stdout. A baseline Release native run of the size-1 probe passed.

Verified effect-only output: `none` and
`direct` each have `2*N+1` MSL116 findings; `allowed` and `pure` have none.
Every root in `none` should select
`root_N -> hub -> leaf_000000 -> sink`. Preserve all diagnostic positions,
ordering, shortest paths, equal-label ties, declaration barriers, cycles and
function/file permission intersection in any fix. Other lint families may also
report findings; compare MSL116 separately and retain the complete output.

## Environment and installation

Linux x86_64, kernel 6.18.57, AMD EPYC 9V74, 5 visible CPUs, managed shared VM.
Initially neither `ms`, `rustc`, nor `cargo` was on PATH; `target/release/ms` and
`target/debug/ms` were absent. The initial `make build` failed before compilation:

```text
cargo xtask runtime
make: cargo: No such file or directory
make: *** [Makefile:32: runtime] Error 127
```

After explicit owner authorization, official rustup installed pinned Rust 1.99.1
into `/workspace/effect-rust/{cargo,rustup}`. An actual compiled Rust test passed.
`make build` then passed with workspace-local `CARGO_HOME`, `RUSTUP_HOME`,
`TMPDIR` and `XDG_CACHE_HOME`; no protected cache or toolchain was accessed.
Rust: `rustc 1.99.1 (58cf8f9c3 2026-10-13)`. Release uses the repository's
unmodified profile and forced frame pointers. The original main binary was
preserved as `/workspace/effect-rust/ms-baseline`; candidate as `ms-candidate`.

Live work checked before investigating: [#3481](https://github.com/manuscript-lang/manuscript/pull/3481)
is merged at the inspected main revision;
[#3351](https://github.com/manuscript-lang/manuscript/pull/3351) is open and unrelated.
The earlier chain/worklist fix is in [#3138](https://github.com/manuscript-lang/manuscript/pull/3138).
No overlapping open effect PR was returned by the live search.

## Independent static review and completed checks

An independent GPT-6 Astra reviewer at high reasoning confirmed the operation
count and source expressibility against the exact revision above. Excluding
`main`, the probe has `2*N+2` nodes and `3*N` edges, with `2*N+1` violations
containing `6*N+3` path labels. The reviewer emphasized stable ordering among
equal labels and first-edge diagnostic positions; selecting the globally
smallest sink would not necessarily preserve the existing path choice.
This review does not approve an implementation or establish measured gains.

The implementation passed 1,500 generated-graph comparisons against the original
BFS, explicit cycle/equal-label/hidden-effect cases, a wide shared graph, and a
130-effect full-result oracle with permission intersections and entry/project
flags. All 373 checker/tooling tests and workspace all-target Clippy passed.

## Production measurements

`baseline-2026-11-10` retains five trials plus one warmup per case. At N=2000,
`ms check` medians were 523.550 ms wide, 138.472 ms permitted and 124.819 ms
direct-call. `sparse-baseline-2026-11-10` adds sparse and many-effect controls.

`paired-2026-11-10` retains eleven alternating pairs plus warmups for sizes
1/20/500/1000/2000, seven graph modes, and both check/lint: 1,680 process records.
All returned zero and matched complete stdout/stderr plus expected effect counts.
The N=2000 wide check medians are 542.889 → 129.422 ms, with median paired
candidate/baseline ratio 0.23725; lint medians are 546.571 → 144.836 ms,
paired ratio 0.25757. All eleven pairs improved for both commands.

Small controls require qualification. In the 41-pair check repeat,
`direct-1` was −1.42% paired median (15/41 slower), while `none-1` was +1.19%
(24/41 slower). These mixed-sign observations and order effects do not establish
a consistent small-control slowdown, and do not prove zero slowdown. The 41-pair
lint repeat reduced the initially flagged direct-1 estimate to +0.65% (23/41
slower). Allowed/pure/cyclic controls had mixed signs and no consistent material
slowdown. Use the paired ratios and sign counts in `results/`, not ratios of
separate medians, when interpreting controls.

The final 21-pair project controls passed exact output checks: hello paired ratio
0.95439 (6/21 slower), e2e driver 0.97860 (8/21), and current programs benchmark
1.00119 (11/21). The initial inventory `.ms.ref` control could not parse on the
baseline because it retains removed `let`/`if let` syntax. Its failure is retained
in the initial projects archive; no inventory measurement or fix is claimed.

Seven-pair uncached Release native-build controls passed at widths 20/500/2000.
At 2000, medians were 571.246 → 185.319 ms, paired ratio 0.31877; all seven
candidate builds were faster. Every produced program exited 0 with empty stdout
and stderr. At width 20 the paired ratio was 0.99101 (2/7 slower).

These initial results compare variants on base `d1ea6ce16`.

## Current-main confirmation

Both release CLIs were rebuilt on `ae87acedab5641ffac4179b17e3e0dc442fcca0e`
with the same pinned toolchain and build settings. Eleven alternating pairs
confirm the N=2000 wide check: 541.374 → 132.124 ms, paired ratio 0.24696,
all eleven faster. Seven uncached native-build pairs give 590.936 → 187.970 ms,
paired ratio 0.31568, all seven faster; all native outputs still exit 0 and are
empty. The small native case has paired ratio 0.99846 (3/7 slower).

The short current-main check run flagged direct-2000 at +6.56% (9/11 slower)
and sparse-2000 at +4.96% (7/11). The retained 41-pair repeat did not reproduce
those losses: direct ratio 0.99832 and sparse 0.99962, both 20/41 slower.
Pure and permitted ratios were 0.99314 (16/41) and 0.98637 (17/41).
This rules out a consistent loss of the initially flagged size in that repeat;
it does not prove zero overhead. Small noisy cases and all raw results remain
in the archives, including unfavorable samples.

The current-main real-project controls have paired ratios 0.99488 for hello,
1.00226 for the e2e driver, and 1.00901 for programs (4/11, 6/11, 7/11 slower).
Every check/lint/build/project pair matched full output and exit status.
The current-base rerun passed all 373 checker/tooling tests, workspace formatting,
all-target Clippy with warnings denied, `make repo-check`, and `make bench-check`.
The first benchmark gate also found the archived historical inventory scratch copy
with removed syntax. After verifying its retained archive byte-for-byte, all transient
run trees were moved outside the source tree; the unchanged gate then passed.
The initial failure log is retained; no gate or tracked test was modified.
Current run directories and command logs are prefixed `current-` in `results/`
and `validation/`. Binary hashes are recorded in each run's metadata.

Before publication, main advanced to `225377d1441fac93d78f22419d5db961bfb52d49`
(review-facts and hover changes). The candidate rebased cleanly; the effect source
diff is byte-identical to the measured patch. All 374 checker/tooling tests, formatting, workspace Clippy and repository checks
passed again on that head. Hosted CI remains required. Timings above belong to the stated ae87 base.

Peak RSS from the exploratory harness is unusable: every main paired sample
reports 162,304 KiB. Both harnesses hash full executables in the parent, which
can leave a resident-memory floor inherited by children. No memory improvement
or memory-nonregression claim is made. Instruction counts were unavailable
(`perf` and `valgrind` absent). Python records retain wall/CPU/fault measurements.

## Reproduction and evidence interpretation

The canonical driver is `bench/tools/effect_reachability.ms`, using the existing
Manuscript benchmark helpers. Its samples use pipes, unlike the exploratory
Python runs' file redirection; compare variants within a run, not absolute times
across harnesses. All measured processes were pinned to CPU 0 externally.
This shared VM is not isolated from other host activity.

```sh
MS_CACHE=off taskset -c 0 target/release/ms run bench/tools/effect_reachability.ms -- OUT BASE CANDIDATE 41 1,20 none,direct,pure,allowed check
```

Arguments are output directory, baseline CLI, candidate CLI, repetitions,
comma-separated sizes, comma-separated modes, and action (`check`, `lint`,
`build`, `projects`, or `summary-check`/`summary-lint`). Build runs verify native
exit status and output; projects checks hello, the e2e driver and current programs.
Recorded commands and binary/input/output hashes identify every sample. Repeated
identical exploratory outputs are losslessly deduplicated into `.stdout.gz` and
`.stderr.gz`; raw sample values are unchanged.
Complete run directories, including generated input bytes, are retained as
`results/<run>.tar.gz`; extract into this directory to restore their original
relative paths. Summary/metadata JSON stays directly readable under `results/`.
The exact measured Rust patch and build/test logs are in `validation/`.

Independent Astra reviews found no blocking algorithm/implementation defect and
verified the paired records. They required the sparse-demand work budget, the
additional control repeats, and the RSS qualification above.

Issue publication was denied by automatic approval review as outside explicit
issue authorization; no issue was created or retry attempted. An issue-publication
approval request is pending. This does not establish any PR or merge readiness.
