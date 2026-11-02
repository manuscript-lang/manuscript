# Rejected ASCII decoding experiment, 2026-10-31

**No production optimization is retained.** The [unapplied patch](candidate.patch)
is preserved because valid ASCII gains repeatedly accompany a rejection regression.
The strongest current-main control regresses by 7.8%; the campaign rejects it.
New benchmark/test coverage and experimental evidence are retained.

Baseline: `d4a94aa9283348133542078e22ccaa3b2c9dc348`. The unapplied candidate changes
only the ordinary Manuscript implementation of `ascii_decode` in
`stdlib/encoding.ms`; its signature, accepted bytes, error identity, and output
are unchanged. No compiler, native runtime, lifetime, or platform mechanism changes.

The original validates a copied byte list, maps it into an integer scalar list,
and constructs text from those scalars. Validated ASCII bytes already encode the
same UTF-8 text, so the candidate calls the existing UTF-8 decoder directly. An
empty-input return avoids conversion work. The copied byte list and its existing
validation remain; this does not eliminate the remaining gap on invalid data.

## Historical results and rejection decision

Nanoseconds per complete call; medians of five interleaved process trials, each
with five timed samples. The Rust control uses unrestricted inlining:

| case | before ns | after ns | Rust ns | after/before |
| --- | ---: | ---: | ---: | ---: |
| ascii.valid.0 | 4.82 | 2.27 | 7.44 | 0.471x |
| ascii.valid.7 | 22.08 | 12.32 | 34.68 | 0.558x |
| ascii.valid.56 | 69.21 | 25.45 | 29.97 | 0.368x |
| ascii.valid.4095 | 3945.36 | 1122.70 | 197.17 | 0.285x |
| ascii.valid.1048579 | 1026775.79 | 285778.75 | 206896.24 | 0.278x |
| ascii.unicode.accent.2048 | 45.01 | 47.88 | 6.55 | 1.064x |

Valid nonempty inputs improve by 1.8–3.6x on this host. Before/after ranges are
disjoint for every valid-input size in both completed campaigns. The 4,095-byte
case remains about 5.7x slower than Rust, and the 1,048,579-byte case about 1.38x
slower. This is not a language-wide parity claim.

**There is a small reproducible rejection regression:** the 4 KiB homogeneous
accent input takes about 2–3 ns longer (4.5% in the full campaign, 6.4% in the
optimized-Rust repeat), with disjoint process-median ranges. An initial independent review considered this a possible small tradeoff. The
current-main repeat strengthens it to 7.8%, so the optimization is rejected under
the campaign regression rule. Its application-level impact and cause are not
established; it must not be called noise or a regression-free change.
The 2 MiB emoji rejection ratio changes from 1.024x to 1.072x with overlapping
process ranges; those data do not establish a stable bound or an all-clear.
Moving the empty check to the extracted list, before or after validation, did
not remove the observed accent penalty; those checks are retained in `results/`.

The [full 68-case comparison](results/final/summary.json) covers 23 ASCII cases,
17 existing regex extraction/replacement cases, 20 existing capture-shape cases,
and eight existing binary/encoding controls. Every case, operation count,
successful producer status and sample count agrees. Unchanged regex and binary
control medians all remain within 5% in this run. Their raw process outputs,
medians, ranges and CVs are retained; this is a profiling observation, not a CI
performance threshold.

The [second ASCII comparison](results/optimized-rust/summary.json) uses an
idiomatic optimized Rust control without an inlining restriction. The first
full run used `#[inline(never)]` at the Rust decode boundary; its source and all
measurements remain as historical evidence. The second Rust comparison is the
basis for the table above. Neither comparison substitutes Rust errors or
Unicode rules for the Manuscript contract.


## Current-main repeat

Baseline main `3cfde58b6` includes four frontend merges after the original
baseline. Both before/after compilers were rebuilt on that revision with the same
native archive; local candidate source state was `0aef4769d38623ea8c6a7c14d838a05c2e70d835`.
That local commit is not a published ref: the exact source is preserved as
[`candidate-encoding.ms.txt`](candidate-encoding.ms.txt) and `candidate.patch`,
and its SHA-256 matches the recorded source hash in `environment.json`.
The [current-main records](results/current-main/summary.json) repeat all 68 cases
in five balanced rounds, using unrestricted optimized Rust. The relocatable
`run.py` was exercised end to end and validates explicit case sets and Rust sample
counts; its metadata records actual host CPU/quota.

- `ascii.valid.0`: 4.81 → 2.26 ns (0.470x); Rust 7.43 ns.
- `ascii.valid.7`: 21.84 → 12.49 ns (0.572x); Rust 35.21 ns.
- `ascii.valid.56`: 68.31 → 25.72 ns (0.377x); Rust 30.20 ns.
- `ascii.valid.4095`: 3922.00 → 1123.41 ns (0.286x); Rust 195.95 ns.
- `ascii.valid.1048579`: 1019984.92 → 289368.53 ns (0.284x); Rust 212693.61 ns.
- `ascii.unicode.accent.2048`: 45.13 → 48.64 ns (1.078x); Rust 6.60 ns.

The rejection ranges remain disjoint: before 44.60–45.31 ns; after 47.07–53.79 ns. Unchanged regex/binary control ratios span 0.986–1.025x. These controls do not excuse the specific ASCII rejection regression. No further source/layout/lifetime investigation was attempted outside the permitted scope.

## Method

Linux x86-64 6.18.57, AMD EPYC 9V45, five exposed CPUs and a four-core cgroup
quota. All timed producers are pinned to CPU 0; local builds and tests are
stopped during measurements. Rust is 1.99.1 (`58cf8f9c3`, 2026-10-13).
The normal Release Manuscript build uses the repository-pinned LLVM 23.1.1 tools,
which were available in the cache; benchmark stderr contained no fallback.
Both compiler binaries embed the same native runtime archive. Rust is compiled
with `-C opt-level=3 -C overflow-checks=yes` for the same static musl target.
Compiler, Rust executable, benchmark and source hashes are recorded in each
`environment.json`.

Each process prepares inputs and verifies complete expected output/errors before
measurement. The ASCII motif is seven bytes (`Az09`, space, newline, NUL), with
explicit byte-count assertions. Empty, seven-byte, 56-byte, 4 KiB and 1 MiB cases,
malformed UTF-8 at both ends, valid non-ASCII UTF-8 at both ends, homogeneous
accents and emoji are included. Successful timed results reach `keep` through
their byte length; invalid results are compared with `EncodingError.InvalidData`
on every iteration. Rust black-boxes the input and complete owned result, uses
`is_ascii`, and returns an owned string; its allocator, validation implementation,
and result-consumption mechanism differ. Tiny-case comparisons include those
whole-call costs.

Five balanced process rounds alternate before/after order and place Rust before
or after the pair. Warmup/calibration and input preparation are outside the timed
samples; each target sample lasts 100 ms. ASCII uses five timed samples, unchanged
controls three. Build/startup costs are excluded. Exact historical measurement
scripts are saved as `final_run.py` and `optimized_run.py`; `run.py` makes their
same sampling protocol relocatable and independently checks the declared case
sets and counts (23/17/20/8).

## Memory

`memory.ms` performs 32 decodes of a one-MiB ASCII input and checks the total
output length. Separate Release executables are measured with the existing
[native RSS launcher](../representative/rss.c), so the Python parent's inherited
high-water mark does not dominate the child result. All three fresh runs report
12,416 KiB before and 4,224 KiB after. These are observed process peak RSS values,
not allocation-call counts or logical capacities. The removed integer scalar
list explains an eight-byte-per-input-byte intermediate at the source type level;
no allocator or generated-code investigation is claimed.

## Rejected alternative

The public-API-only [UTF-8/count candidate](rejected-utf8-count.ms.txt) first
converts to UTF-8 text and accepts it only when byte length equals scalar length.
That predicate is correct, and ASCII inputs are much faster, but valid Unicode
rejection regresses drastically: one MiB of accents changes from about 15.4 us
to 890 us, and two MiB of emoji from 31.7 us to 1,458 us. These single exploratory
processes took three samples per case; they suffice to reject the candidate,
not to claim a precise general speed ratio. The paired Unicode benchmark sources
and raw results are retained. This candidate is not applied.

## Validation and limits

- New called tests `ASCII decoding preserves every seven-bit byte including NUL`,
  `ASCII decoding rejects every high byte at either end`, and `ASCII decoding
  rejects valid non-ASCII UTF-8`: pass in Release and Debug. They cover all 128
  ASCII values, all 128 high byte values at either end, empty input, embedded
  NUL/DEL, valid Unicode rejection, and a sliced view after a multibyte prefix.
- Existing encoding fixture: four tests pass in Release and Debug, including
  Base64, hex, UTF-16 and Latin-1 vectors and errors.
- All four affected benchmark files type-check; all 68 cases execute successfully.
  The native RSS programs check their output length on every fresh invocation.
- Rust formatting, Manuscript formatting, repository invariants, and
  `git diff --check` pass. No public declaration or generated API documentation
  changes are needed.
- Full workspace/conformance, lifetime/parity, backend-specific, network and
  Windows investigations are outside this campaign's permitted local scope;
  they were not substituted with another validation route. Required CI remains
  enabled. macOS/Windows timings and a replay after future independently merged campaign PRs are not claimed.

## Publication verification after interruption

The GitHub tree upload was interrupted before publication; a read of the expected
tree returned not-found and no branch existed. The evidence-only change was then
rebased onto main `81b804d58`. Production `stdlib/encoding.ms` still matches that
main exactly. The current native runtime and release compiler rebuilt
successfully; the three new ASCII tests passed in Debug and Release, all four
existing encoding tests passed in Release, and repository invariants and saved
patch applicability passed again. This is functional verification of the
restored implementation, not a new timing acceptance claim.

## Reproduction

Build baseline `3cfde58b6` using the repository instructions, save its `ms`
binary, apply `candidate.patch`, rebuild and save the candidate binary. Both
must use the same pinned native runtime, Rust toolchain and build settings.
Use the benchmark files from this change for both compilers:

```sh
rustc -C opt-level=3 -C overflow-checks=yes \
  --target x86_64-unknown-linux-musl bench/perf/ascii-decode/rust.rs -o /tmp/ascii-rust
python3 bench/perf/ascii-decode/run.py \
  --before /tmp/ms-before --after /tmp/ms-after --rust /tmp/ascii-rust \
  --baseline-revision 3cfde58b6 --output /tmp/ascii-comparison
```

Use `--ascii-only` to replay the optimized-Rust comparison. `rustc` and the
compiler commands should use the repository's pinned installation; set
`XDG_CACHE_HOME` to a writable cache when the default home cache is read-only.
For RSS, build `memory.ms` with each saved compiler, compile the existing `rss.c`,
and invoke `rss metrics.json program` three times per version. Keep timing and
RSS trials separate.
