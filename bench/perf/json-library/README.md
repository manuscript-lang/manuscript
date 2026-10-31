# JSON float writer controls, 2026-10-31

**All production experiments are rejected; production JSON, active tests and root
dependencies are unchanged.** Zmij1.0.23 plus exact midpoint arithmetic preserved
all sampled bytes and improved hard-float arrays about1.84x, but the actual
pristine-main dependency-graph comparison reproduced a roughly1.5% tiny-file-read
cost. The signal is modest/noisy (9/12 long pairs), and no mechanism or universal
slowdown is established. Under the campaign's strict protected-common-path rule,
keep the existing implementation. Preserve the target gain and counterexample.

A corrected Ryu alternative regressed Unicode writing. A later attempt to remove
the old15-digit scaling path passed exact-output checks but regressed dedicated
precision classes25–52%. That path remains justified. Candidate source patches,
tests, dependency snapshots and complete observations are archived below.

This is a **native library component** study: Rust callers invoke
ms_std_json::Writer and idiomatic Serde JSON on equivalent values. It is not
compiled-Manuscript, generated-encoder or universal language parity. All following
before/after tables describe unshipped experiments. Rust parser ratios are null:
Manuscript retains original number lexemes while Serde normalizes some spellings,
so parse timings are diagnostic or same-contract before/after controls only.

The latest canonical [dated baseline](../baseline-2026-10-28.md) is a profiling
reference from a different machine; its numbers are not mixed into these ratios.
All reported ratios below compare the same host, inputs, semantics and release
settings. Instruction/page-fault counts were not captured; perf and Valgrind were
unavailable. No profiler installation, credential or security-setting change was attempted.
RSS evidence is retained and is not allocation counts.

## Builds and method

Initial base: `f33f13359a02b59467f042eb67d6ecd06d706c7a`.
Integrated base: main `09e0eb7e66b0437d257dd5e2702855a158c35739` plus this patch,
combined core tree `ef276266f2fe7d8640146ed4f4c8360f43f7c8ef`.
For each component pair, the before build restores only the original JSON library
source; both use the candidate manifest and same dependency versions. The exact
Zmij version is also Serde JSON's existing conversion dependency.

Host: Linux x86_64, AMD EPYC 9V45, available CPUs 0–4; shared host, no exclusive-CPU
claim. Rust/Cargo 1.99.1 (`58cf8f9c3`, LLVM 23.1.1), release opt-level 3, panic abort,
repository frame pointers, same host allocator. Final Serde JSON is pinned to
**1.0.154**, features `float_roundtrip` and `arbitrary_precision`. Builds and
measurements were sequential; no other campaign build ran in this container during
measurement. Setup and printing are excluded; operation allocation/destruction is included.

Eight deterministic arrays cover empty/tiny, 512 ASCII strings, 256 Unicode strings,
256 dense escaped strings, 1,024 integers, 512 common decimals and 512 seeded finite
float patterns. Four additional 1,024-float arrays cover midrange, large whole floats,
exact halfway values, and notation/extreme/subnormal neighbors. Every write checks
its whole output inside the timed loop. Setup decodes complete typed values and
checks float bits exactly. Manuscript before/after output bytes must match.
Parse trees are observable and node counts checked; invalid-input Rust comparisons
are not attempted because the duplicate/error policies differ.

Twelve interleaved trials use all six orders twice, with baseline calibration to
at least 50ms (up to one million operations). Longer A/A controls target about 700ms
per baseline process. Keep all samples and outliers. Full source/binary/toolchain
identities are in [the final environment](results/2026-10-31/final-precision/environment.json),
[edge environment](results/2026-10-31/final-precision-edges/environment.json),
[artifact/oracle hashes](results/2026-10-31/artifacts.json) and focused provenance.

## Final measurements

Nanoseconds per array. Before/after >1 is a gain; after/Rust >1 is remaining writer
overhead. Rust parse comparisons are deliberately omitted. Full distributions
include median, MAD, min and max.

| Case | Operation | Before ns | After ns | Rust writer ns | Before/after | After/Rust |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| empty | write | 28.9 | 29.2 | 12.2 | 0.988× | 2.400× |
| empty | parse | 45.5 | 47.5 | — | 0.957× | — |
| tiny | write | 42.4 | 42.6 | 18.6 | 0.995× | 2.292× |
| tiny | parse | 88.2 | 89.6 | — | 0.984× | — |
| ascii | write | 3645.0 | 3546.9 | 3351.4 | 1.028× | 1.058× |
| ascii | parse | 3943.4 | 4054.9 | — | 0.973× | — |
| unicode | write | 5113.6 | 5077.8 | 18006.4 | 1.007× | 0.282× |
| unicode | parse | 6982.5 | 7060.0 | — | 0.989× | — |
| escapes | write | 61961.9 | 61683.5 | 26020.9 | 1.005× | 2.371× |
| escapes | parse | 94625.0 | 96873.3 | — | 0.977× | — |
| integers | write | 7848.3 | 7824.2 | 5504.8 | 1.003× | 1.421× |
| integers | parse | 5541.5 | 5443.8 | — | 1.018× | — |
| decimals | write | 5721.4 | 5725.2 | 6760.0 | 0.999× | 0.847× |
| decimals | parse | 3821.1 | 3826.4 | — | 0.999× | — |
| hard-floats | write | 49460.7 | 27066.5 | 6796.9 | 1.827× | 3.982× |
| hard-floats | parse | 5499.3 | 5499.9 | — | 1.000× | — |
| midrange | write | 99443.7 | 53828.1 | 13316.5 | 1.847× | 4.042× |
| whole | write | 127429.8 | 52616.2 | 13224.4 | 2.422× | 3.979× |
| halfway | write | 285947.9 | 37284.5 | 16555.8 | 7.669× | 2.252× |
| thresholds | write | 72949.5 | 39513.9 | 15490.3 | 1.846× | 2.551× |

[Long writer controls](results/2026-10-31/review-focused/summary.json) measure
integer baseline A/B at 7944/7770ns and candidate 7806ns; Unicode 5071/5107→5074ns;
hard floats 50123/50008→27522ns. These do not establish a meaningful protected-writer
regression. They supplement rather than replace the full matrix.

A small uncertainty remains visible: empty parsing is 45.49→47.52ns in the short
run. The [long confirmation](results/2026-10-31/review-empty-parse/summary.json)
is 46.39/45.96→47.43ns, a possible 1–1.5ns marginal cost. Candidate MAD is 2.83ns;
paired candidate-minus-mean(A,B) differences change sign (slower in 5/12 trials,
paired median −1.14ns). These observations do not establish a consistent material
regression, and do not justify saying every control is flat. Both long runs record
the exact driver hash, invocation, binary hashes and input-summary hash.

[Separate RSS](results/2026-10-31/final-precision-memory/samples.json) includes setup,
semantic validation and 1,000 guarded writes in fresh processes: six cases × six
balanced trials × three labels = 108 records. Typical whole-process peaks are
roughly 1.2–1.7 MiB, with no material increase. This is not allocation counts or a
claim about arbitrary input sizes. The conversion Buffer and normalization arrays
are on the stack; the Writer's existing output allocation remains.

The actual native change also passes all eight compiled-Manuscript TOML regression
controls on main 09e0: [full cross-control](results/2026-10-31/toml-json-impact/summary.json),
288 balanced observations, medians within 1.3%. A separate helper-toggle experiment
found a TOML common-path regression already on untouched main, leading to
[revert PR #2124](https://github.com/manuscript-lang/manuscript/pull/2124).
That decision is independent of this JSON candidate; the attribution control
keeps the merged TOML helper unchanged on both sides. Historical helper-toggle
records remain separate and do not establish a JSON regression.

## Byte compatibility and rejected alternatives

A direct Ryu 1.0.23 substitution initially changed 160 of one million spellings,
although every changed value read back as the same float. For the exact float
1658206780088562.25, the existing decimal is 1658206780088562.3; Ryu selected
1658206780088562.2. Negative cases differ correspondingly. The
[recorded examples](variants/naive-ryu-differences.json) are exploratory: the full
naive stream and binary were overwritten before archival, so this is not a
complete reproducibility artifact or the retained correctness proof.

Rust 1.99.1's official core `num/imp/flt2dec/mod.rs` specifies closest-shortest
formatting; `strategy/dragon.rs` rounds exact positive ties upward (`2*mant >= scale`).
Zmij supplies shortest correctly rounded digits. Factoring the binary significand
identifies an exact decimal midpoint without float arithmetic. For positive
`x=m*2^q` with odd m, `2*x/10^p` is odd exactly when q=p−1 and the appropriate
powers of five divide. Checked integer arithmetic computes those odd units, then
`units/2+1` selects the old upper decimal. Relevant shortest midpoint counts fit in
u64. Independent review checked divisibility, bounds, normalization and carry.

The complete one-million-value signed/nonfinite/decimal/seeded-bit oracle is
byte-identical before/after: 36,563,797 bytes, SHA-256
`5bcd38bdba0747ea6a073f899cf3360d0283eacb90987ed1eb1aba255c00f860`.
Direct digit tests additionally cover every binary exponent bucket, decimal-power
neighbors and targeted binary midpoint families, bypassing existing fast paths.
This is sampled and algebraic evidence, not exhaustive enumeration of all f64.

A corrected Ryu candidate retained the standard formatter only for exact midpoints.
It improved hard floats 1.888× but regressed Unicode writes about 9.1% in long A/A
controls: 4849/4873→5294ns, so it was rejected. The
[unapplied patch](variants/rejected-ryu.patch), manifest, lockfile,
[full records](results/2026-10-31/rejected-ryu-full/summary.json) and
[long records](results/2026-10-31/rejected-ryu-focused/summary.json) are retained.
The archive patch uses zero context (apply with `git apply --unidiff-zero` against
the pinned original library); reconstruction matches the rejected source exactly.
No backend or placement tuning was attempted. The Zmij replacement changes the
actual conversion/tie-correction algorithm and repeats the protected controls.

All initial A/A, initial Zmij, exploratory edges and pre-arbitrary-precision
integrated records remain in their named directories. Their numeric Rust parse
ratios are unmatched; only final writer comparisons above support claims.
Escaped input JSON retains decoded-byte hashes where raw CR inputs cannot be
committed under repository rules. RSS rows are complete aggregates; duplicate
per-child metric files are omitted. Per-case outputs and escaped input records are
losslessly bundled in each directory's `outputs.json` / `inputs.json`: original
filenames are keys; `utf8` encodes the exact file bytes and `sha256` verifies them.
Every bundled entry was decoded and compared byte-for-byte before removing the
individual duplicate file, keeping the PR reviewable without discarding evidence.

## Verification and limits

Passed: three scalar tests (`decimal_midpoints_are_detected_without_float_scaling`,
`binary_midpoint_families_and_neighbors_keep_the_closest_decimal`,
`shortest_digits_match_the_standard_scientific_formatter`), all 13 writer tests
including `halfway_shortest_decimals_keep_the_existing_spelling`, three failure,
two recorded-oracle and one roundtrip tests (22 total). The new source regression
`JSON floats retain halfway ties and notation boundaries` passes on the untouched
f33f baseline compiler and integrated candidate compiler. It covers positive/negative
halfway decimals, thresholds and the pre-existing −0 spelling; an initial fixture
expectation of 0 was corrected using the baseline oracle. Existing scalar and
nonfinite/budget source controls pass. On pinned 09e0, four TOML quoting and 43 YAML
source tests pass, including Unicode blanks, block keys and empty entries.

Affected crate/control Clippy with warnings denied, workspace/control formatting,
repository checks, license generation/freshness, Python syntax and whitespace
checks pass. `make bench-check` is blocked by existing obsolete `Optional[T]` syntax
in `bench/perf/competence/ms/src/main.ms:241` (separately reported as #2034).
Full workspace/native conformance, FFI-only lifetime tests, Debug JSON, backend,
cleanup/ownership, HTTP and Windows investigations were not run under campaign
exclusions. Normal required CI remains enabled. After merging main ead45f307 (combined tree c80c33897), the JSON native source,
runtime source and root dependencies remain unchanged. Normal native/CLI rebuild,
source float/scalar/nonfinite controls and all five newer YAML physical-key tests
pass. Final merged-main replay remains required after publication.

Remaining writer/Rust gaps include empty/tiny setup, dense escaping, integer output
and residual float-presentation overhead. These are not clean claims. This patch
addresses scientific conversion only; parser coverage and generated codecs are
not a general performance result.

## Reproduction

Use matched worktrees and manifests on the pinned integrated base. Restore only
`crates/ms-std-json/src/lib.rs` from initial f33f13359 for before; use the candidate
source for after. Build both with:

```sh
cargo build --release --locked --manifest-path bench/perf/json-library/Cargo.toml
```

Copy `json-library-controls` and `float-edges` from that manifest's release target
directory to absolute artifact paths, then run:

```sh
python3 bench/perf/json-library/run.py --before /absolute/before --after /absolute/after --rust /absolute/before --output /fresh/full --revision BASE_PLUS_PATCH
python3 bench/perf/json-library/edges.py --before /absolute/edges-before --after /absolute/edges-after --rust /absolute/edges-before --output /fresh/edges --revision BASE_PLUS_PATCH
python3 bench/perf/json-library/focused.py --before /absolute/before --after /absolute/after --summary /fresh/full/summary.json --output /fresh/long --cases integers unicode hard-floats
python3 bench/perf/json-library/focused.py --before /absolute/before --after /absolute/after --summary /fresh/full/summary.json --output /fresh/empty --cases empty --operation parse
cc -O2 bench/perf/representative/rss.c -o /absolute/rss
python3 bench/perf/json-library/memory.py --before /absolute/before --after /absolute/after --rust /absolute/before --rss /absolute/rss --environment /fresh/full/environment.json --output /fresh/memory
/absolute/before float-oracle > /absolute/before.tsv
/absolute/after float-oracle > /absolute/after.tsv
cmp /absolute/before.tsv /absolute/after.tsv
```

Drivers reject producer failures, invalid counts/checksums, changed Manuscript
bytes and incomplete sample sets before writing final summaries. Build/input work
is outside measurement. For source tests build normally with `cargo xtask runtime`
and `cargo build --release --locked -p ms-cli`; use writable XDG_CACHE_HOME if needed.
Never bypass native archive freshness checks.

## Updated main after shared byte-search changes

The conflict-resolution head `34697faf851073b330443f6d86b6dbfdadcd6b20` integrates
main `d439d4e4b`, including the TOML revert and shared byte-search changes. Both
native controls were rebuilt on this combined tree, restoring only current main's
original JSON library source for before. The full 720 observations and 108 RSS records
are retained under [updated-main](results/2026-10-31/updated-main/summary.json),
[edges](results/2026-10-31/updated-main-edges/summary.json) and
[memory](results/2026-10-31/updated-main-memory/samples.json).
Hard floats improve 1.844×; extra float cases improve 1.852–7.861×.
The million-value byte oracle still matches the original hash.

A short tiny-parse shift prompted another long A/A check:
89.56/86.54→87.01 ns, with overlapping distributions and baseline A/A variation
larger than the candidate/B shift. Empty writes measure 29.38/29.47→29.64 ns in the
long replay; this possible 0.17–0.26 ns cost remains within their observed variation.
See [tiny parse](results/2026-10-31/updated-main-tiny-parse/summary.json) and
[empty writes](results/2026-10-31/updated-main-empty-write/summary.json).
All 22 scoped Rust tests, source float regression, affected Clippy, workspace
formatting, repository and license checks pass on the conflict-resolution head.
The wiki now preserves both independent lessons and correctly records the TOML
helper's later revert. No GitHub approval was submitted; required CI remains enabled.

Main `81b804d58` / #2139 was then merged into validation head
`8390117f612681f0369cbd814af8c0f5fc8a05dd`. All native benchmark source hashes
remain identical; the native binaries are unchanged and their hashes are recorded.
The normal native/CLI build, all 22 scoped Rust tests, three source float/scalar
controls, Clippy, formatting, repository and license checks pass again.
A fresh 720-observation balanced replay is retained under
[snapshot-replay](results/2026-10-31/snapshot-replay/summary.json) and
[snapshot-edges](results/2026-10-31/snapshot-edges/summary.json): hard floats 1.820×,
additional float cases 1.834–7.585×. The tiny-parse marginal variation persists
(about 3.5% in this short run); the longer identical-binary controls above remain
important context and do not establish a material regression. No Rust parser
comparison is claimed. Required CI must pass on the updated PR head.


Main `024af5e2e544f7c9d2ccccc1c333b92b70db0ef3` was merged into validation head
`63f6886c8d2709633e28d328fa7b6ca5c4228075`, preserving the newer YAML comment,
encoding, visibility and bench-maintenance changes. The independent performance
lessons were preserved during wiki conflict resolution. Both component controls
were rebuilt on this tree and are byte-identical to the earlier reviewed binaries
(before SHA256 `1e9aff4b43d124362184f88966097b7c214ca6d475fc90575fbc2f2c8d78e3ed`,
after `519584d9194280815925c6b4488d70f98d165e5ca832369a4df2d794b9747e49`).
Fresh balanced [full](results/2026-10-31/main-024-replay/summary.json) and
[edge](results/2026-10-31/main-024-edges/summary.json) replays retain all720 observations:
hard floats improve1.842x; additional float cases1.852–7.557x. Short common write
medians show no new material regression; earlier long controls apply to these
exact same binaries. All22 scoped JSON Rust tests and the normal native/CLI build
pass on this integrated tree. Required CI must rerun on the updated PR head;
post-merge combined-main replay remains required.


## Expanded compiled TOML controls on main024

A separate-worktree comparison on024 exposed possible large-Unicode timing costs.
Its [complete1,224 observations](results/2026-10-31/toml-main-024-separate/summary.json)
remain retained as discovery; checkout differences confound candidate attribution.
We therefore repeated normal runtime/CLI builds in **one worktree**, with the same
manifests, exact dependency graph, target and source paths. The baseline restores
only current-main JSON lib.rs; the candidate uses the reviewed replacement.
This is an isolated algorithm toggle, not a pristine-main dependency graph.

[Source/runtime/build identities](results/2026-10-31/toml-main-024-identical/build-identities.json)
and fresh [full results](results/2026-10-31/toml-main-024-identical/summary.json)
cover1,224 observations over11 parse/stringify,6 error,8 writer and11 read cases,
including1MiB inputs. All four corresponding before/after TOML, error, writer and
read executable pairs are **byte-identical**. These produced-executable results
are therefore A/A variation; even directional label differences cannot establish
an algorithm-specific TOML cost. Different runtime-archive hashes alone do not
establish an executable change. No backend/cache/lifetime mechanism was inspected
to explain the identity or earlier differences, and no build-speed claim is made.

Each measured iteration reads fresh external UTF-8 input; setup and printing are
excluded, cached-file ingestion and full-output equality are included. Equivalent
Rust toml0.9.8 values validate every complete valid output; MS before/after bytes
agree. Six errors compare exact MS diagnostics only. All observations, actual
counts, outputs and payload hashes remain retained, including the unfavorable
separate-worktree cohort. The compressed
[harness snapshot](variants/toml-control-scan-harness.json.gz) maps exact original
relative filenames to UTF-8 source and SHA256; its manifest hashes every file and
both packed/unpacked bundles. Restore it under bench/perf/toml-control-scan for the
recorded commands. No temporary source copy is added to the active benchmark tree.
Independent review verified the identical executables and scoped attribution limit.


## Final actual-graph counterexample and rejection

Newer main `72a0274844d124b7f3184b738f2826f82a8a619c`, including the regex change,
was independently combined with reviewed converter commit46712ee1a in integration
head `075bc92918422bfcc2a47889378039de2e31dfd8`. The normal runtime/CLI builds pass.
Candidate validation passes22 scoped JSON Rust tests,3 source JSON controls,
22 source TOML controls (including every ASCII/C1 admission and normalized-location
case) and41 YAML source tests. The baseline scalar_tests filter selected zero and
is explicitly not counted as candidate coverage; its18 existing JSON tests passed.

Fresh [component](results/2026-10-31/main72-component/summary.json) and
[edges](results/2026-10-31/main72-edges/summary.json) retain720 observations:
hard floats1.837x, additional floats1.817–7.490x. These are real component gains,
with hard arrays still about4x the Rust writer on this host. They do not establish
a safe overall change.

The actual pristine-main comparison restores the **original** root manifests and
locked graph for before, then applies the actual source/dependency change for after,
in the same worktree and source/target paths. This differs from the earlier
candidate-manifest-only A/A cohort. All four generated TOML/error/writer/read pairs
now differ. [Build identities](results/2026-10-31/main72-actual-graph/build-identities.json)
match pristine main72 and the exact integration tree. No concrete source/build
confound was found by independent review.

The [complete1,224-observation matrix](results/2026-10-31/main72-actual-graph/summary.json)
passes all full-value/byte/error checks. Tiny-file reads lose about1.47%. Longer
[read controls](results/2026-10-31/main72-read-long/summary.json),144 observations,
give A/B/candidate medians2235.64/2231.20/2267.93ns: **+1.545%** versus mean baseline
medians, paired median+37.72ns, slower in9/12 trials. Baseline MADs7.56/10.58ns,
candidate MAD29.15ns; the effect is modest and its ranges overlap. The paired cost
exceeds the17.22ns median absolute A/A difference and reproduces the full-matrix
signal. Fields32 reads have a smaller/noisier+1.19% signal (8/12 slower), while
empty/comment controls are close. No mechanism is inferred from these observations.

[Long roundtrips](results/2026-10-31/main72-roundtrip-long/summary.json),72 observations,
show a possible tiny+0.68%/48ns marginal cost (10/12), and do not retain the short
Unicode slowdown. These mixed controls are all preserved. Earlier identical-binary
A/A results cannot clear this actual-graph comparison. Given the protected-path
rule, the converter is rejected conservatively; this is not proof of a universal
1.5% slowdown or of its cause. No backend/cache/lifetime investigation or placement
variant was attempted to explain or tune it away.

Fresh [component RSS](results/2026-10-31/main72-memory/samples.json) has108 unique
records and no material increase. Setup and complete semantic checks are included;
these are whole-process peaks, not allocation counts. They do not overturn rejection.
All production, active test, root lockfile and license inventory changes are restored.
The exact [converter patch](variants/rejected-zmij-main72.patch) preserves those
unshipped changes, including tests and dependencies. The original benchmark lockfile
and four-case edge sources/drivers are archived alongside it for exact historical
replay; the active harness adds precision-class controls for future work.

## Rejected removal of the scaling path

A distinct simplification removed short_digits and its power table, using Zmij
right after the existing integer and short_fraction paths. Independent pretrial
review required its intended success classes: small decimals and5–15-digit
fractions. No dependency/ABI change was added by this trial. The complete
[matrix](results/2026-10-31/short-digits-full/summary.json),576 observations, and
[seven edge classes](results/2026-10-31/short-digits-edges/summary.json),252 observations,
retain every result. Some other float classes gain3–7%, but fraction5,
fraction15 and small-decimals before/candidate ratios are0.756/0.801/0.659:
about32%/25%/52% slower. The extra success-class controls establish that the old
scaling path still earns its code. No further variant was attempted.

All22 scoped Rust tests pass. Complete before/after one-million-value streams are
byte-identical,36,563,797 bytes, SHA256
5bcd38bdba0747ea6a073f899cf3360d0283eacb90987ed1eb1aba255c00f860;
[oracle identities](variants/short-digits-oracle.json) retain the result. Streams
remain in local campaign artifacts and are reproducible from the pinned generator;
they are not duplicated in this Git payload. The
[unapplied removal patch](variants/rejected-short-digits.patch) applies on top of
the archived converter. The active seven-case harness reconstructs its inputs.
Production and all performance experiment edits are restored. These bounded passes
found no further verified safe optimization; known Rust gaps and untested paths
remain, so this report does not declare the whole lane or language clean.
