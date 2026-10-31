# Byte search: 2026-10-31

`Bytes.index_of_byte` scanned every byte individually. On this Linux x86_64 host,
long misses and late hits were much slower than an optimized Rust `memchr` baseline.
The focused change scans the first 16 bytes as before, then delegates the remaining
suffix to the already locked memchr 2.8.3 dependency. Empty/end-start searches
return absence before any search. Public signatures, byte values, absolute offsets,
negative starts and absence behavior are unchanged.

Baseline main: `d4a94aa9283348133542078e22ccaa3b2c9dc348`. Rust 1.99.1; host and
compiler/native/executable hashes are in [environment.json](results-2026-10-31/environment.json)
and [host.txt](results-2026-10-31/host.txt). Manuscript was built with the normal
Release command; companion metadata reports `cranelift`. No backend investigation
was performed. Rust uses Cargo release, checked arithmetic and the repository's
frame-pointer flags. Its non-inlined wrapper and black_box guards prevent work
elimination; their overhead matters for tiny calls, so those numbers do not establish
universal language parity. Neither side includes input setup or output in timing.

## Accepted comparison

[All 130 distributions and paired deltas](results-2026-10-31/accepted/summary.csv)
and [all 2,340 raw rows](results-2026-10-31/accepted/samples.csv) are retained.
One checked warmup per side precedes all six permutations of before/after/Rust,
pinned to CPU 0, with builds complete. Each side appears twice in each order position.
Every producer's complete case inventory, byte sizes, iteration counts and checksums
passed the independent Python bytearray.find oracle. All results feed a checked
checksum. Median time ratios and median paired deltas are distinct statistics.
Six rounds describe these samples, not confidence intervals or other machines.

| Case | Before ns | After ns | Rust ns | Median paired delta ns |
| --- | ---: | ---: | ---: | ---: |
| empty miss | 1.37 | 1.12 | 2.03 | -0.24 |
| one-byte miss | 1.63 | 1.57 | 2.47 | -0.06 |
| seven-byte miss | 3.46 | 3.37 | 3.77 | -0.26 |
| first hit, 1 MiB | 1.63 | 1.58 | 2.75 | -0.06 |
| miss, 4 KiB | 1134.66 | 26.01 | 17.31 | -1108.45 |
| miss, 1 MiB | 420014.82 | 7043.20 | 7135.99 | -413075.17 |
| last hit, 1 MiB | 470790.04 | 6934.32 | 7177.75 | -463868.46 |

The 1 MiB miss/late-hit medians improve about 60x/68x, with faster paired times
in all six rounds. The scalar-only miss regression found in review is fixed;
small first-hit costs remain visible in the complete table. The largest median
paired penalty is 0.23 ns (`near16_64`).
The 16-byte scalar prefix retains inexpensive nearby hits; long-input offsets
1, 7, 15, 16 and 17 are explicit controls. Search uses no new allocating call;
allocation counts and RSS were not measured.

## Broader and rejected controls

[Broader controls](results-2026-10-31/controls/record.json) ran six alternating pairs
on CPU 0: line splitting 16 cases/192 rows, normalization 100/1,200, reversal
83/996. All output/status/checksum guards passed. No case exceeded both 5% slower
median and 1 ns median paired cost with at least five of six slower pairs. That
is a descriptive screening rule, not a CI threshold or a claim that every case
improved; all raw samples and summaries, including unfavorable medians, are retained.
These programs use unchanged source and the same compiler, with matched before/after
native archives. Final combined merged-main remeasurement remains pending merge.

The [first 130-case candidate](results-2026-10-31/rejected-empty-end/record.json)
regressed empty/end-start searches by roughly 1–1.6 ns in all six pairs because
it reached vector search on an empty suffix. The next candidate fixed those
but regressed a one-byte miss from 1.64 to 2.65 ns (paired +0.97 ns, six of six
slower pairs); independent review required this be disclosed. Its [raw evidence
and exact patch](results-2026-10-31/rejected-short-miss/record.json) and
[broader controls](results-2026-10-31/rejected-short-miss-controls/record.json)
remain separate. The accepted candidate returns early for an empty searchable
range and skips vector search after a scalar-only miss. No rejected phase is
pooled with the accepted samples.
[Exploratory 80-case phases](results-2026-10-31/exploratory-80/) stay separate;
they predate the added near-hit controls and are not pooled with final evidence.

## Reproduce

Build the compiler/runtime normally, preserve the baseline native archive, and
build this exact source with that compiler and archive. Apply the focused patch,
rebuild the runtime and preserve a second program built with that archive. Use
MS_RT_LIB to select each archive, keeping compiler/source fixed:

```sh
MS_RT_LIB=BASELINE_ARCHIVE target/release/ms build \
  bench/perf/bytes-index/main.ms --build-type Release -o BEFORE
MS_RT_LIB=PATCHED_ARCHIVE target/release/ms build \
  bench/perf/bytes-index/main.ms --build-type Release -o AFTER
CARGO_TARGET_DIR=/tmp/bytes-index-rust cargo build --release --locked \
  --manifest-path bench/perf/bytes-index/rust/Cargo.toml
python3 bench/perf/bytes-index/compare.py BEFORE AFTER \
  /tmp/bytes-index-rust/release/bytes-index-rust NEW_OUTPUT_DIRECTORY --cpu 0
```

The output directory must be new. Stop concurrent builds/CPU work before timing.
The runner validates warmups and all measured producers before reporting complete
results; an empty-producer smoke test verifies failure without a summary. Other failures leave complete=false and the available partial evidence.
`identities()` constructs its expected results with Python's independent byte search.
The additional called source tests exercise boundaries, every hit offset through
129 bytes, high-bit bytes, successful nonzero starts, earliest hits, and extreme starts.
Both Release and Debug pass with the candidate archive. Workspace Clippy, Rust
formatting, repository checks, and five scoped pure-search nextest tests pass.
Full workspace nextest/conformance was not run locally because this campaign
excludes denied ownership/lifetime mechanisms. Required CI remains in force.
