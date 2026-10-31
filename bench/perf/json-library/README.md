# JSON float writer controls, 2026-10-31

The retained optimization replaces the native JSON library's general scientific
formatter fallback with Zmij 1.0.23 and an exact integer correction for the existing
upward tie rule. Existing short-decimal paths, JSON notation thresholds, signed
zero, nonfinite handling and budgets are unchanged. Hard-float arrays improve
**1.827×**; the four additional float controls improve **1.846–7.669×**.

This is a **native library component** study. Rust callers invoke
`ms_std_json::Writer` and idiomatic Serde JSON on the same host, producing the same
abstract JSON values in the same order. The established numeric presentation rules
can produce different equivalent spellings and byte lengths; both are recorded.
This is not compiled-Manuscript, generated-encoder or universal language parity.

Rust parser timings are **diagnostic only**: Manuscript's arena parser retains
original number lexemes, while Serde's Value representation has different lexical
and normalization contracts. The final Rust control enables `arbitrary_precision`
for exact numeric precision, but still normalizes some spellings. All final Rust
parse ratios are null. Earlier numeric parse ratios are unmatched historical
experiments and must not be used as performance evidence. Native parser
before/after ratios remain useful because that implementation's contract is unchanged.

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
No backend or placement tuning was attempted. The Zmij replacement changes the
actual conversion/tie-correction algorithm and repeats the protected controls.

All initial A/A, initial Zmij, exploratory edges and pre-arbitrary-precision
integrated records remain in their named directories. Their numeric Rust parse
ratios are unmatched; only final writer comparisons above support claims.
Escaped input JSON retains decoded-byte hashes where raw CR inputs cannot be
committed under repository rules. RSS rows are complete aggregates; duplicate
per-child metric files are omitted.

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
exclusions. Normal required CI remains enabled. Final merged-main replay remains
required after publication.

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
