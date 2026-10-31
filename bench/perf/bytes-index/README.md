# Byte search: 2026-10-31

`Bytes.index_of_byte` scanned every byte individually. The final candidate checks
the first byte directly, scans the next 16 bytes with the existing word-at-a-time
helper, then uses the already locked memchr 2.8.3 dependency for the suffix. It
returns absence before searching an empty range/suffix. Public signatures, byte
values, earliest absolute offsets, negative starts and absence behavior stay unchanged.

On the first integrated 220-case comparison, 1 MiB misses and late hits improve
about 31x while preserving inexpensive nearby hits. The earlier scalar-prefix
candidate is rejected after a combined-main replay exposed boundary-hit costs.
All original and unfavorable measurements remain separately labeled below.

The [fresh main 988 integration replay](results-2026-10-31/fresh-main-988/README.md)
repeats all 220 byte cases and all 199 affected controls with a rebuilt compiler
after resolving the documentation conflict. Miss/late-hit speedups remain about
32x/33x; second-byte hits retain a real 0.26–0.39 ns paired cost. Every adverse
distribution remains, including small unrelated-control increases. The new Rust
reversal reference exposes a separate gap; it is not a reversal optimization.

## First integrated comparison (main 3cf)

Base main: `3cfde58b6216ae4db54aeb3ae4e22ee7d527e323`; native sources match the
original baseline `d4a94aa92` through that main revision. Rust 1.99.1; Linux x86_64
host details are in [host.txt](results-2026-10-31/host.txt).
[Environment and exact patch](results-2026-10-31/word-prefix-final/environment.json)
and [producer record](results-2026-10-31/word-prefix-final/byte220/record.json)
retain compiler, native archive, program, source, validator and input hashes.
Manuscript uses the normal Release command; its companion metadata reports
`cranelift`. No backend investigation was performed. Rust uses Cargo release,
checked arithmetic and the repository's frame-pointer flags. Its non-inlined
wrapper and black_box guards prevent work elimination; that overhead matters for
tiny calls, so tiny numbers alone do not establish language parity.

One checked warmup per side precedes all six permutations of before/after/Rust,
pinned to CPU 0, after builds finish. Each side appears twice in each position.
[All 3,960 raw rows](results-2026-10-31/word-prefix-final/byte220/samples.csv) and
[all 220 distributions/paired deltas](results-2026-10-31/word-prefix-final/byte220/summary.csv)
are retained. The independent Python bytearray.find oracle validates each case's
input bytes, iteration count and checksum; missing/duplicate cases or failed
producers reject. Untimed preflights check exact Optional presence and offsets;
timed results feed the checked checksum. Setup and output are outside timing.
A ratio of medians differs from a median paired delta. Six rounds describe these
samples, not confidence intervals or other machines.

| Case | Before ns | After ns | Rust ns | Median paired delta ns |
| --- | ---: | ---: | ---: | ---: |
| one-byte miss | 1.69 | 1.80 | 2.25 | 0.11 |
| seven-byte miss | 3.14 | 3.14 | 3.71 | -0.00 |
| second-byte hit, 1 MiB | 2.12 | 2.44 | 2.42 | 0.31 |
| offset 8 hit, 1 MiB | 3.65 | 2.40 | 2.39 | -1.24 |
| offset 9 hit, 1 MiB | 3.97 | 2.75 | 2.42 | -1.20 |
| offset 16 hit, 1 MiB | 5.54 | 2.74 | 2.47 | -2.54 |
| offset 17 hit, 1 MiB | 5.52 | 4.26 | 2.44 | -1.26 |
| miss, 1 MiB | 238307.19 | 7638.38 | 7268.63 | -230434.83 |
| last hit, 1 MiB | 238390.83 | 7577.23 | 7529.56 | -230499.38 |

At 1 MiB, misses/late hits and the tested offsets 7, 8, 9 and 15–18 improve
in all six paired rounds. Small
costs remain: the second-byte hit adds about 0.31 ns in the 1 MiB case, and the
one-byte miss adds about 0.11 ns. The largest median paired penalty is 0.33 ns (`near1_4096`).
These tradeoffs are retained, not relabeled as noise or universal parity. Search
introduces no allocating call; allocation counts and RSS were not measured.

## Broader controls and checks

[Final broader controls](results-2026-10-31/word-prefix-final/controls/record.json)
run six alternating pairs on CPU 0: line splitting 16 cases/192 rows,
normalization 100/1,200, reversal 83/996. All output/status/checksum guards pass.
No case exceeds both 5% slower median and 1 ns median paired cost with at least
five of six slower pairs. This is a descriptive screen, not a CI threshold or a
claim that every case improves. All distributions, including adverse medians,
remain. Sources, executables, compiler, native archives and build selections are
recorded for every suite. The [200-case word-prefix exploration](results-2026-10-31/word-prefix-final/exploratory200/record.json)
stays separate from the final phase adding word-boundary offsets 8/9. Its exact
Manuscript/Rust source snapshots were not fully retained; original hashes and
reconstruction checks remain. The complete final 220-case inputs are provided.

The two called source tests pass in Debug and Release with the candidate runtime:
`byte search preserves offsets across scanner boundaries` checks empty through
129-byte inputs, every hit offset, high-bit bytes, boundary/extreme starts and
successful nonzero starts; `byte search returns the earliest hit at or after start`
checks repeated hits. Five scoped pure-search nextest model tests and workspace
all-target Clippy with warnings denied pass; Rust formatting and repository
invariants pass. An empty-producer smoke check rejects with complete=false and
no summary. Full workspace nextest/conformance was not run locally because this
campaign excludes denied ownership/lifetime mechanisms. Required CI stays enabled.
A final merged-main campaign replay remains pending merge; this is a pinned,
integrated current-main branch replay.

## Retained rejected and earlier phases

- [First scalar prefix](results-2026-10-31/rejected-empty-end/record.json):
  empty/end-start searches added roughly 1–1.6 ns in every pair by reaching vector
  search on an empty suffix. Exact patch and raw data remain.
- [Second scalar candidate](results-2026-10-31/rejected-short-miss/record.json):
  fixing empty ranges still regressed a one-byte miss 1.64→2.65 ns, paired +0.97 ns,
  slower in six of six rounds. Its [broader controls](results-2026-10-31/rejected-short-miss-controls/record.json)
  remain separate.
- [Subsequent scalar phase](results-2026-10-31/accepted/record.json), historically
  named accepted: the empty suffix fix initially left only fractional-nanosecond
  costs; it was not final integration evidence. Its [199 broader controls](results-2026-10-31/controls/record.json)
  remain intact.
- [Scalar integration with main 3cf](results-2026-10-31/integration-main-3cf/environment.json):
  the final exact-preflight phase exposed +1.1–1.3 ns at several offsets 16–17,
  with five/six or six/six slower pairs. This candidate was held and replaced by
  the shared word-prefix algorithm. Both byte phases and all broader controls
  remain; no compiler/placement cause is claimed.
- [Initial 80-case exploration](results-2026-10-31/exploratory-80/): predated the
  added near-hit controls. None of these historical phases are pooled with the
  final 220-case comparison. The original native/compiler result metadata stays
  attached to its own phase; absolute times and speed ratios vary between phases.

## Fresh-main readiness follow-up

A later [8dd79f417 replay](results-2026-10-31/fresh-main-8dd/README.md) initially
flagged 63-byte reversal at +6.63%, paired +9.76 ns, seven of eight slower pairs.
This temporarily held the word/vector PR. Two predeclared full-suite repeats show
+2.21%/+1.49%; identical-binary A/A shows a +5.01% median difference. The material
penalty is unconfirmed, not disproved; a smaller persistent cost remains possible.
All original/repeat/A/A phases and paired ranges remain. The same experiment's
separate ASCII-normalization prototype is rejected for its repeated composition
cost. A distinct first-byte candidate is rejected too; [their complete evidence
PR](https://github.com/manuscript-lang/manuscript/pull/2125) changes no runtime
code. Read the follow-up before interpreting the earlier
zero-screen results as proof that unrelated operations are unchanged.

The subsequent [988 replay](results-2026-10-31/fresh-main-988/README.md) has a
+0.81% 63-byte reversal median with paired -2.49 ns, two of six slower. Maximum
unrelated-control median increases are 2.97% lines, 3.72% normalization and 3.17%
reversal; full signs, ranges and smaller consistent costs remain explicit.
Independent review finds no new blocking regression at this checkpoint and
supports word-only publication with the disclosed tradeoffs. Normal required CI
and actual merged-main replay remain necessary; the entire lane is not declared
clean.

## Reproduce

Build the compiler/runtime normally, preserve the baseline native archive, and
build this exact source with that compiler/archive. Apply the focused patch,
rebuild the runtime, and build a second program with that archive. Keep compiler
and source fixed, using MS_RT_LIB to select each archive:

```sh
MS_RT_LIB=BASELINE_ARCHIVE target/release/ms build \
  bench/perf/bytes-index/main.ms --build-type Release -o BEFORE
MS_RT_LIB=PATCHED_ARCHIVE target/release/ms build \
  bench/perf/bytes-index/main.ms --build-type Release -o AFTER
CARGO_TARGET_DIR=/tmp/bytes-index-rust cargo build --release --locked \
  --manifest-path bench/perf/bytes-index/rust/Cargo.toml
ms run bench/tools/bytes_index_compare.ms -- BEFORE AFTER \
  /tmp/bytes-index-rust/release/bytes-index-rust NEW_OUTPUT_DIRECTORY --cpu 0
```

The output directory must be new. Stop concurrent local builds/CPU work before
timing. The runner validates warmups and every measured producer before marking
results complete; failures leave complete=false and available partial evidence.
The scoped .gitattributes preserves original CSV producer line endings; the
manifest hashes exact committed bytes. No executable or native archive is published.
