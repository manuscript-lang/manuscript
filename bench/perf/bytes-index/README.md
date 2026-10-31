# Byte-search campaign preparation (unmeasured)

Prepared on 2026-10-31 against main
`d4a94aa9283348133542078e22ccaa3b2c9dc348`. No production patch is included.
No speedup, correctness pass, final-head pass, or merge readiness is established.

`Bytes.index_of_byte` in `crates/ms-rt/src/vec.rs` uses a scalar
`iter().position` scan. The existing `memchr` dependency is a candidate for
long scans. The Rust baseline uses `memchr` 2.8.3 with checked arithmetic and
an opaque, non-inlined call, preserving search inputs/results during timing.
Both programs search for byte 255, normalize negative starts to zero, reject
starts beyond length, and return the first absolute matching offset or absence.

The 80 prepared cases cover empty through 1 MiB, early/middle/late matches,
misses, negative starts, exact-end/past-end starts and nonzero offsets.
Setup and output are outside the timed interval. Each case checks an untimed
search and the final checksum. Every result contributes its absolute offset,
or input length for absence, to the checksum. `identities.json` was generated
with an independent Python bytearray.find oracle. This prepares validation;
it does not establish that either executable follows the contract.

After toolchain/download permission is resolved, build the Manuscript source
with the normal Release settings and this Rust crate with `cargo build
--release --locked`. Preserve the actual build metadata and all source,
compiler, native archive and executable hashes. Confirm the source compiles
against the current API before measuring. A release label alone does not
establish the effective backend or optimization.

The existing `../string-lines/compare.py` accepts these columns and identities:

```sh
python3 bench/perf/string-lines/compare.py MS_PROGRAM RUST_PROGRAM samples.csv \
  --pairs 8 --identity-file bench/perf/bytes-index/identities.json
```

Run serially with no builds or other CPU work. It validates warmups, producer
status, exact case inventory, operation counts/checksums and positive timings;
it retains all samples and reports medians/ranges. Before accepting a patch,
repeat baseline/patch/Rust and full affected controls on final combined main,
including tiny/first-hit paths that may regress with vector search setup.
Do not claim allocator or memory improvements for a pure search change; no
allocation behavior is changed or measured here.

Other static candidate: materialized String.split and Bytes.split repeatedly
call `find` rather than keeping a searcher for a multi-byte separator. The
existing `Needle` helper may avoid repeated setup. This has not been measured
and must retain empty-separator and max_parts behavior. Reverse and normalization
remain untested in this campaign; historical rollback evidence is not a fresh
current-main result. Regex, encoding and denied compiler/lifetime/network scopes
are excluded.

Campaign coordination paused additional downloads and use of the newly installed
toolchain pending explicit permission. Before that message arrived, local Rust
1.99.1 installation, a baseline runtime/CLI build and the Rust baseline build
had completed. No benchmark executable was run. GitHub CLI PR listing returned
Forbidden; a connector read occurred before the subsequent instruction forbidding
alternate-route retries. No further GitHub access or publication was attempted.
