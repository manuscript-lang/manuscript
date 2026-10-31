# Final accepted-parser replay — 2026-10-31

The actual merged main `e9e03b4f331edb9e9e03adcf623bdc8a38781527`
contains both accepted fixes: [#2072](https://github.com/manuscript-lang/manuscript/pull/2072)
moves accumulated type trees into suffix wrappers; [#2099](https://github.com/manuscript-lang/manuscript/pull/2099)
reuses failed type parses in nested index expressions. This record preserves
final combined-main controls, including shallow costs. It adds no production code.

These are measurements of the compiler implementation written in Rust, not
Manuscript-generated programs against equivalent Rust programs. No universal
language parity or whole-compiler speedup is claimed.

## Pinned protocol

All three release libraries and the same saved benchmark source were built
sequentially in the same checkout, cwd, default target directory and flags.
`builds.json` records source, library and executable fingerprints and rustc
commands. All variants use Rust 1.99.1, release opt-level 3, debug 1, panic abort,
and frame pointers. Host: Linux x86_64, kernel 6.18.57/glibc 2.41, AMD EPYC 9V45 VM.
Runs and children are pinned to CPU 0, with no concurrent local builds or
benchmarks; host isolation is not asserted.

- Before either fix: `d4a94aa9283348133542078e22ccaa3b2c9dc348`.
- Actual suffix-only merged main: `649ddeb9a2fb91eb36d1eb074842eaaa4ee370fc`.
- Actual combined merged main: `e9e03b4f331edb9e9e03adcf623bdc8a38781527`.

The existing [timing runner](../parser-suffix/run.py) with `--suite suffix`
and `--suite speculation`,
[generated outcome runner](../parser-speculation/parity.py) and shared
[harness](../parser-suffix/bench.rs) were used unchanged from combined main.
The harness SHA-256 is recorded in `builds.json`. Each timing process warms three
passes then measures at least 100 ms in batches of 16. Ten balanced interleaved
AB/BA pairs per case, shuffled with seed 1729, preserve all 300 suffix and 420
speculation samples. Setup, I/O and exact validation are outside timing;
parsing/source retention/destruction are inside. Work counts and checksums are
verified. The standard-library corpus has 45 files.

## Final results

Values are median microseconds per pass; full distributions are in the archives.
The suffix comparison is before either fix versus combined main. The indexing
comparison is actual suffix-only main versus combined main, isolating #2099.

| Comparison | Input | Baseline µs | Combined µs | Baseline / combined |
| --- | --- | ---: | ---: | ---: |
| Before both | Optional suffix depth 512 | 64723.303 | 441.965 | 146.444x |
| Before both | Result suffix depth 256 | 21984.154 | 303.585 | 72.415x |
| Before both | 256 ordinary generic optional types | 219.865 | 203.605 | 1.080x |
| Before both | 256 plain declarations | 103.349 | 104.455 | 0.989x |
| Before both | Tiny function | 0.540 | 0.552 | 0.977x |
| Before both | Standard-library corpus | 4847.169 | 4811.666 | 1.007x |
| Suffix-only | Nested indexing depth 256 | 1336.724 | 56.043 | 23.852x |
| Suffix-only | Nested indexing depth 128 | 343.840 | 28.137 | 12.220x |
| Suffix-only | Nested indexing depth 64 | 87.819 | 14.445 | 6.080x |
| Suffix-only | Mixed nested/flat expressions | 95.631 | 92.744 | 1.031x |
| Suffix-only | Standard-library corpus | 4800.535 | 4789.417 | 1.002x |
| Suffix-only | Tiny function | 0.525 | 0.553 | 0.950x |
| Suffix-only | Flat name index | 0.954 | 1.010 | 0.945x |
| Suffix-only | Nested indexing depth 2 | 0.922 | 0.955 | 0.965x |
| Suffix-only | Flat value index | 1.050 | 1.074 | 0.978x |
| Suffix-only | 256 plain declarations | 103.917 | 104.830 | 0.991x |

The tiny and flat-name controls cost about 28 ns (+5.3%) and 56 ns (+5.8%) in
the isolated indexing comparison. Depth 2 costs about 33 ns (+3.6%). These are
preserved costs, not universally flat/noisy controls. Corpus timing is essentially
unchanged and deep indexing improves strongly; the earlier review accepted a
small observed shallow costs for removal of the quadratic rescan. No extra favorable
trials, flag changes or layout tuning were used to erase these final observations.
Independent final-replay review recommends retaining both merged fixes; this
bounded evidence does not justify an immediate rollback. That recommendation
retains the measured shallow costs and is not a claim of regression freedom.

## Correctness and checks

Both timing suites validate exact syntax trees/dumps, including IDs and positions,
before timing. The speculation replay also compares 220 exact successful/error
outcomes (including depth limits 990/999/1000/1001) and six recovery outcomes.
`generated-outcomes.json.gz` preserves all 1,000 seed-1729 comparisons: 364
accepted and 636 rejected, all identical between actual suffix-only and combined
main. This is deterministic coverage, not exhaustive fuzzing.

On actual combined main, these passed:

- `cargo test --locked -p ms-syntax`
- `cargo clippy --locked -p ms-syntax --all-targets -- -D warnings`
- `cargo fmt --all --check`
- `cargo run --release --locked -p ms-repo-check`

Normal required remote CI passed before both production PRs merged. Excluded
backend, ownership/lifetime, runtime, Windows and network investigations were
not performed locally; those paths are not declared clean.

## Discovery coverage and unresolved findings

`discovery/` preserves the read-only discovery report, producer/probe sources,
243 initial samples, 40 flat-layout follow-up samples and 80 function-depth
baseline samples. The report predates this final replay; its subsequently
identified header-depth candidate was tested and held as documented in
[the complete lexer decision record](../lexer-header-depth/README.md).
No other source-backed actionable issue emerged from that bounded pass over
16 families (layout, declarations, bodies, collections, comments, escapes,
interpolation and recovery). This is not an exhaustive clean claim.

Remaining limits are explicit: the lexer tail-check candidate remains held for
an unexplained common-control regression; both tested token-reservation changes
were rejected for common regressions; a flat-layout size-regime transition lacks
causal attribution; successful ambiguous generic applications grow the AST and
would require changing excluded consumers/representation. These remain
unresolved rather than being silently accepted or labeled clean. Allocation
counts were not measured in this final replay; earlier RSS/capacity evidence and
its limits remain in the original experiment records.
