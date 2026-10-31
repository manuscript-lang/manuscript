# Literal search and materialized split discovery preparation

This is an unmeasured discovery candidate, not a confirmed slowdown or accepted
optimization. No production edits, PR, benchmark timing, compiler investigation,
or denied mechanism investigation were performed.

## Pins and artifacts

The parent selected frozen source tree
`58691f4e3e9143c47ddc5801902e9aba8a8633ab` (its word-search branch merged with
main `98854115f`) and the unchanged baseline runtime archive. This is not the
latest remote main; final current-main replay remains necessary.

- Paired source: `text-discovery.ms`, `text-discovery.rs`
- Untimed MS verification source: `text-discovery-verify.ms`
- Binaries: `text-discovery-ms`, `text-discovery-rust`, `text-discovery-ms-verify`
- Independent Python oracle/generator: `prepare.py`
- All 63 ordered `(input_bytes, iterations, checksum)` identities: `identities.json`
- Every expected result plus input/needle content hashes: `semantics.json`
- Reproducible build and untimed checks: `build.sh`, `verify.py`
- Exact compiler/runtime/source/artifact hashes and check outcomes: `build-and-verify.json`, `SHA256SUMS`
- Source compaction preservation/audit: `pre-compaction/`, `compaction-audit.json`

Compiler: `/workspace/byte-search-evidence/fresh-main-988/ms-compiler`, SHA256
`c0206ad63cab27353feb941a70d4f500dca2856beeb184e4cd98cf3b997a4a85`.
Runtime: `/workspace/byte-search-evidence/fresh-main-988/baseline.a`.
Manuscript uses ordinary Release builds. Rust uses installed 1.99.1, edition
2024, opt-level 3, overflow checks, frame pointers, and no target-cpu override.
No dependency installation or network was needed. The initial build's read-only
home-cache failure was resolved using the normal XDG cache setting under this
directory; no permissions or security settings changed.

## Candidate and existing coverage

`crates/ms-rt/src/string.rs`'s `split_into` loop calls `find` separately for each
nonempty separator match. For a multi-byte separator and long remaining text,
`find` calls `memchr::memmem::find` on each pass. Repeated setup is a plausible
cause worth measuring; these source facts alone do not establish its cost.

Existing `bench/perf/substring-search` controls bounded raw-byte `find`/`rfind`
calls, including repetitive near misses, prose hits/misses and empty needles.
The stdlib split benchmark covers materializing a space-separated ASCII word
list. Existing lines and Bytes.index_of_byte campaigns remain separate.
This preparation adds multi-byte literal separators and public scalar-index
semantics. It does not inspect or change split iterator or resource behavior.

## Exact semantics and 63 cases

18 split cases: empty input with nonempty/empty separators; tiny no-match;
leading/trailing/consecutive separators; overlapping candidates; NUL separator;
Unicode scalar splitting; max_parts 0/1/2; capped Unicode scalar splitting;
64/4096 24-byte fields separated by `||`; 1024 Unicode fields separated by
`§§`; repetitive 256-byte separator near miss; dense periodic separators;
1 MiB no-match; large field input capped to two pieces.

15 search scenarios, each measured separately for contains, index_of and
last_index_of: empty/empty, empty/nonempty, tiny first/last, tiny miss, Unicode
scalar index, Unicode empty needle, overlapping matches, NUL/Unicode, common
prose, late ASCII hit, late Unicode hit, repetitive near miss and haystack
lengths 31/32/33. Full names and expected values are in the identity artifacts.

Rust searches use str::contains/find/rfind; index results convert byte offsets
with `text[..offset].chars().count()` INSIDE the operation. This matches MS scalar
indices, including empty last-match semantics. Comparing raw Rust byte indices
would be a semantic mismatch.

Rust materializes `Vec<String>` using split(...).take(limit).map(str::to_owned).
MS materializes a returned List[String]. max_parts truncates pieces and discards
the remainder; Rust splitn would be incorrect. Empty separators use chars()
without leading/trailing empty fields; empty text then yields an empty list.
Both sides compare every complete result with the Python oracle's explicit
expected list/index and consume a checked checksum. Setup and printing are
outside clocks. Rust uses a non-inline operation and black_box guards. No
identical allocation strategy or universal language parity is claimed.

## Measurement readiness and limits

Run `python3 verify.py` for untimed checks. It executes the SAME Rust binary's
--verify and --inventory modes, and a separately compiled MS verification
companion containing all 63 exact output checks. The MS timed executable also
has preflight and per-operation guards, but it has not been executed yet.

Default producer output is `case,input_bytes,iterations,elapsed_ns,checksum`.
Iteration count is a predeclared approximate 8 MiB work budget, clamped to
16..100000, with estimated bounded/early-hit work used for capped and nearby
search cases. The original input-size-only preparation was too short for the
large capped split control; it is retained under `initial-input-sized/`. Neither
preparation has timing data. This adjustment was made before any timings.

Expected long uniform/periodic strings are now built with repeat/concatenation
before entering measurement functions on both sides. Pre-compaction sources and
binaries are preserved under `pre-compaction/`. All 63 identity values and the
complete semantic/content-hash artifact remain byte-identical. Generated MS
source shrank from 1,124,385 to 10,317 bytes; Rust from 1,130,229 to 16,952 bytes.
This changes setup/source artifacts only; no timings preceded the compaction.

No independent timings are authorized in this child. The parent must coordinate
serial repeated interleaved runs, validate all identities, retain distributions
and adverse cases, and replay on final current main before making a speed claim.
Rust retains the constructed corpus across measurements while MS constructs
each case immediately before calling its measurement; both exclude setup.
The 63-case corpus does not establish that untested search/split paths are clean.
