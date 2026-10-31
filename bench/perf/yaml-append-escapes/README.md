# Rejected direct YAML escape append, 2026-10-31

**Rejected; production and active tests are unchanged.** Directly appending fixed
hex digits improves dense cached-file serialization 2.203x and the large dense
case 2.518x. A sparse late escape regresses 4.44% in all 12 long paired trials.
The large sparse case also regresses. The gains do not justify the protected costs.

## Contract and pinned experiment

Base: main `024af5e2e544f7c9d2ccccc1c333b92b70db0ef3`. JSON float optimization
#2126 is absent from both sides. Only YAML quote_text and its single-use hex4
helper changed: append `\\u00` and two lowercase hex characters into the existing
StringBuilder, removing radix formatting, padding and the temporary four-digit
string. The guarded range is 0..31 or 127..159, so both nibble indices are valid.
Named escapes, other Unicode, keys, results and byte budgets retain their contract.
No parser logic or public API changed. Independent pretrial review checked this
rationale and the helper's single caller.

The [unapplied patch](variants/candidate.patch) reconstructs the candidate against
the pinned base with git apply --unidiff-zero. [Build identities](variants/build-identities.json)
record source/binary hashes and normal build commands. Runtime and Release CLI
builds ran in one worktree with the same pinned graph; after changing the embedded
YAML source the CLI and both producers were rebuilt. The native archive itself
was unchanged. No build-speed claim or backend/cache/lifetime investigation is made.

Host: Linux x86_64 AMD EPYC9V45, CPUs0–4, shared host. Rust/Cargo1.99.1, LLVM23.1.1;
MS Release; Rust opt-level3 panic abort and repository frame-pointer flags.
Rust serde_yaml_ng0.10.0 serializes the same dynamic one-string mapping. Every whole
output is decoded and compared with the input string; MS before/after bytes must
agree. Different equivalent YAML quoting is allowed. Ratios describe the tested
serialization workflow, not identical quote kernels or universal language parity.

Primary inputs are read fresh from an external UTF-8 file **inside every measured
iteration**, then mapped and serialized. Setup/printing are excluded; cached-file
I/O, map creation, full equality guards and destruction are timed. Counts calibrate
separately to50ms (cap one million), and all actual counts are retained. Twelve
interleaved trials use all six orders twice. No other local build or benchmark ran
concurrently. The readiness-marker probe changes input after setup; both exact
measured producers reject the change with status1 and no timing output.

## Complete primary and longer results

[396 primary observations](results/2026-10-31/file-full/summary.json) cover11 cases,
including large ASCII, sparse and dense inputs. Nanoseconds per full cached-file
operation; before/candidate >1 is a gain. Read costs are not subtracted.

| Case | Before ns | Candidate ns | Rust ns | Before/candidate |
| --- | ---: | ---: | ---: | ---: |
| empty | 2258.7 | 2275.6 | 1923.3 | 0.993x |
| tiny | 2434.9 | 2443.9 | 2130.4 | 0.996x |
| common | 2514.6 | 2491.1 | 2394.2 | 1.009x |
| ascii16k | 11798.1 | 11811.6 | 70534.3 | 0.999x |
| unicode16k | 37254.1 | 37174.5 | 54653.8 | 1.002x |
| sparse | 87960.3 | 94178.0 | 70965.4 | 0.934x |
| dense | 319620.5 | 145107.0 | 96357.5 | 2.203x |
| mixed | 135266.6 | 135434.5 | 68634.5 | 0.999x |
| ascii1m | 858941.8 | 871146.3 | 4973296.1 | 0.986x |
| sparse1m | 5756873.3 | 5941436.0 | 4942788.2 | 0.969x |
| dense1m | 30323395.0 | 12044516.6 | 4607686.0 | 2.518x |

One prespecified [long confirmation](results/2026-10-31/file-long/summary.json)
covers common, sparse, sparse1m, ASCII1m and Unicode16k:180 observations over
12 balanced A/A/candidate trials at about700ms per baseline process. Both baseline
labels use the exact same binary.

| Case | Baseline A ns | Baseline B ns | Candidate ns | Paired slower trials |
| --- | ---: | ---: | ---: | ---: |
| common | 2529.4 | 2513.6 | 2510.7 | 4/12 |
| sparse | 88110.3 | 87806.9 | 91867.4 | 12/12 |
| sparse1m | 5692271.6 | 5642014.6 | 5911105.0 | 12/12 |
| ascii1m | 807926.3 | 815255.9 | 815509.2 | 7/12 |
| unicode16k | 37048.9 | 36892.4 | 36727.4 | 6/12 |

Sparse medians88110/87807→91867ns give+4.44%; paired median cost is3896ns, with all12
pairs slower. Sparse1m has a repeatable cost too. Common is flat/improved; ASCII1m
and Unicode controls remain retained. The production source was restored; no
variant or placement search followed this result.

The [guarded reused-value program](results/2026-10-31/guarded-full/summary.json)
retains288 exploratory observations over eight cases. It reuses invariant input;
output guards/checksums alone do not source-prove repeated serialization. Its
2.562x dense result and different sparse direction do not support isolated-writer
or Rust-parity claims, and do not replace the primary fresh-input confirmation.

## Correctness, memory and retained artifacts

Before and candidate both pass36 current YAML tests plus five source regressions:
plain/Unicode; named/control escapes; exact C1 lowercase hex; exact/invalid budgets;
and quoted keys with C0/C1 controls. Those five tests are archived in the harness,
not added to the active suite. No output, error or limit-policy change is retained.

[RSS](results/2026-10-31/memory/samples.json) has90 unique fresh processes: five cases,
six balanced trials and three labels. It includes setup, validation, I/O and three
complete primary operations. MS candidate medians differ by−4KiB across all five
cases, with no material increase. Whole-process RSS is not allocation counts and
does not identify a mechanism or overturn the timing rejection.

The [harness bundle](variants/harness.json.gz) maps seven exact relative source/test
and Cargo filenames to UTF-8 and SHA256; the manifest hashes every entry and both
packed/unpacked bundles. Raw timing/RSS records, commands, full output/input bundles,
byte counts and hashes are retained, including unfavorable cases. All entries were
round-tripped against their originals. The original run.py hash inventory also
contains generated build artifacts because it walks the harness directory; those
incidental hashes are preserved, while the source bundle contains only the seven
explicit source/manifest files. This distinction is documented in build identities.
No cache mechanism was investigated to explain those generated files.

The earlier helper experiment remains available at its
[immutable revision](https://github.com/manuscript-lang/manuscript/blob/43103db76576e22bbc07e07fe8bc2847b2cc9371/bench/perf/yaml-quoting/README.md).
Finished directories removed by later main are not restored. Required CI stays
enabled; full workspace, backend, ownership/cleanup, HTTP, Debug JSON and Windows
investigations were not run under campaign exclusions. Held alias-budget #2083
and untested parser shapes are not declared clean by these writer controls.

## Replay

Use matched checkouts at the pinned base. Materialize the harness under
.artifacts/yaml-append-escapes/harness, save base YAML as baseline-yaml.ms beside
that harness directory, and copy the four Python drivers beside it. Build original
producers, apply the saved patch, rebuild the normal CLI, then build candidate
producers from the same source paths. Build Rust with its exact standalone lockfile.
Run run.py with mode file/guarded and before/after/rust/output paths; focused.py,
probe.py and memory.py accept the complete commands recorded in their metadata.
No improvement from this rejected candidate is shipped or establishes broad clean
status. No GitHub approval is submitted on the user's behalf.
