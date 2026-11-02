# Rejected integer radix parsing optimizations

Measured 2026-10-31 against main `d4a94aa9283348133542078e22ccaa3b2c9dc348`.
**All three candidates are rejected. Production `num.rs` is unchanged.**
Valid-input parsing was slower than an equivalent Rust workload, but each attempted
improvement introduced an error-path regression. This lane remains unresolved;
these measurements do not establish a clean performance pass or Rust parity.
This is distinct from the rejected radix **formatting** experiments in #1959.

## Workloads and equivalence

[`main.ms`](main.ms), [`rust.rs`](rust.rs), and [`repeat.py`](repeat.py) retain the
final producer and measurement protocol. `main.ms` is formatted for repository
checks; [`measured-main.ms.txt`](measured-main.ms.txt) preserves the exact measured
Manuscript source bytes. Both producers set up equivalent inputs
outside their internal monotonic timers, use checked arithmetic, consume every
result, and validate output before successful exit. Rust uses input and output
`black_box` barriers. Native calls keep Manuscript parsing observable.

Valid parsing cycles through 1,000 identical strings: small positive values,
wide positive values, and values starting at signed minimum, in bases 2/10/16/36.
Every cycle element is checked exactly before timing. Timed results contribute
their signed residue modulo 997, and the final result is checked exactly. This
residue checksum alone does not prove every timed result's complete value.

Error controls use 32 or 4,096 maximal digits, or a 4,096-digit string with `!`
at its beginning/end. Exact error messages are checked. Manuscript promises
`InvalidData` for malformed text even after a numerically overflowing prefix.
The Rust error control therefore validates the complete syntax before calling
`from_str_radix`; comparing Rust's early-overflow parser alone would have different
semantics. Success controls also parse 4,096 leading zeros followed by `1`.

Float controls exercise exponential, precision, fixed, and shortest formatting,
including ordinary eighths, signed zero, maximum finite and smallest subnormal
values. Rust normalizes scientific exponent spelling and implements Manuscript's
precision notation thresholds. This handwritten equivalent is not a claim about
a native Rust general-format API. Float checksum controls check all output
lengths and final text, not every intermediate string's contents.

## Three rejected candidates

1. [`sticky-native.patch`](variants/sticky-native.patch): decode once and use
   native-width wrapping arithmetic with sticky overflow. Valid parses improved
   about 24–32%, but arithmetic continued over the entire overflowing suffix.
   Long overflowing/late-invalid inputs regressed **2.4–3.4×**. Rejected.
2. [`native-suffix.patch`](variants/native-suffix.patch): native-width checked
   accumulation, then syntax-only suffix validation using a shared digit decoder.
   Early-invalid inputs regressed **1.53×**, late-invalid decimal **1.58×**, and
   long overflowing decimal **1.066×**, against approximately flat A/A. Rejected.
3. [`conservative-suffix.patch`](variants/conservative-suffix.patch): preserve
   the original `u128` arithmetic and direct digit handling; merge successful
   scans and validate the remaining suffix after overflow with the original-style
   validation loop. Wide valid parsing improved **6–20%**, but early-invalid
   inputs regressed **1.47×**, late-invalid decimal **1.51×**, and long overflowing
   decimal **1.106×**. Rejected. No further variants were measured.

The first candidate's long-input cost follows from its continued arithmetic.
The exact implementation/placement cause of the other regressions is unestablished;
no backend, disassembly, ownership, lifetime, or parity investigation was performed.
Favorable valid-input timings do not justify these tradeoffs.

## Final conservative trial: selected results

Values are median internal ns/operation. Ratios are medians of within-phase
after/before ratios; CPU ratios and every case appear in [`summary.md`](summary.md).

| Operation | Before | After | Rust | Paired ratio | A/A |
| --- | ---: | ---: | ---: | ---: | ---: |
| Wide positive base 2 | 95.64 | 77.44 | 56.53 | 0.805 | 0.999 |
| Wide positive base 10 | 28.25 | 25.95 | 18.01 | 0.913 | 1.001 |
| Wide positive base 16 | 27.52 | 25.89 | 15.86 | 0.941 | 0.997 |
| Small positive base 10 | 7.87 | 7.71 | 4.01 | 0.980 | 1.000 |
| Early-invalid decimal | 2.19 | 3.23 | 0.89 | 1.472 | 0.978 |
| Late-invalid decimal, 4,096 digits | 1157.98 | 1743.21 | 973.77 | 1.509 | 0.998 |
| Overflowing decimal, 4,096 digits | 1173.23 | 1292.83 | 973.33 | 1.106 | 1.011 |
| Leading-zero decimal, 4,096 zeros | 6055.45 | 4934.83 | 3777.82 | 0.820 | 1.003 |
| Ordinary exponential, 2 fractional digits | 112.46 | 113.16 | 173.07 | 1.006 | 0.997 |

The early/late-invalid and long-overflow decimal regressions occurred in all eight
pairs. Baseline valid parsing remains slower than Rust in this workload; Float
controls did not identify a corresponding actionable slowdown. There is no
universal language-performance claim and no retained speedup.

## Configuration and retained samples

Linux 6.18.57 x86_64, AMD EPYC 9V45; four-core CPU quota (`400000 100000`),
16 GiB memory limit.
Every producer was pinned to the lowest available CPU. No build/test ran during
the measured sessions. Shared-host scheduling and outliers remain in the data.

Official Rust/Cargo **1.99.1**, rustc `58cf8f9c35b355199727627d07ae34a4e2846d67`
(2026-10-13), LLVM 23.1.1. Native archives used `cargo xtask runtime`; the frozen
compiler used `cargo build --release --locked -p ms-cli`. Generated programs used
`--build-type Release` and the same compiler/source per pair, selecting each
archive through `MS_RT_LIB`. Default backend selection was left unchanged;
the build sidecars label it `cranelift`. No backend-specific performance claim
is made. Rust controls used the same musl target and frame pointers:

```sh
rustc --edition=2024 -C opt-level=3 -C overflow-checks=on \
  -C force-frame-pointers=yes --target x86_64-unknown-linux-musl rust.rs -o rust-control
```

Each session includes an identical-byte baseline copy for A/A, one warmup and
eight timed phases, rotating case order and all four producer positions, then
reversing those orders. All pair orders/positions balance over eight phases.
Ordinary samples use 300,000 operations; long suffix/leading-zero controls use
4,687. Tiny/output checks use counts 1, 2, and 1,000, with no tiny-call speed claim.
Compilation, setup, process startup and output are excluded from internal timing.
Whole-producer wall/CPU measurements include startup and setup. No outlier is removed.

| Dataset | Producer rows | Tiny/output controls | Warmups | Measured |
| --- | ---: | ---: | ---: | ---: |
| [Sticky native](results/sticky-native.jsonl) | 1,488 | 372 | 124 | 992 |
| [Native suffix](results/native-suffix.jsonl) | 1,584 | 396 | 132 | 1,056 |
| [Conservative suffix](results/conservative-suffix.jsonl) | 1,584 | 396 | 132 | 1,056 |

All **4,656** retained producer invocations succeeded with required identities,
checksums, final text, empty stderr, and bounded timings. The sticky-native Rust
fixed-text error loop lacked an input optimization barrier: those Rust error rows
are **exploratory/excluded**, not performance evidence. Its early-error samples
also used reduced counts. The rejection uses Manuscript before/after long-input
results. Later sessions fix both issues. The corresponding older Rust/runner
sources are retained as `.txt` snapshots. An earlier two-producer exploration had
an ordering flaw and is excluded entirely from this report.

[`artifacts.json`](artifacts.json) records compiler/archive/binary and retained-file
hashes. No allocator, RSS, or instruction-count measurement is claimed. The parser
helpers themselves allocate no buffers before or after; setup-string allocations
are outside the timer. The existing radix-formatting stop rule was respected;
no rejected formatting specialization was repeated.

## Correctness, review and limits

Each patch includes `radix_parsing_preserves_range_and_invalid_digit_precedence`:
all 35 bases, signs, uppercase digits, signed limits, `2^63`/`2^64` neighbors,
long zeros/ones/maximal digits, late-invalid suffixes and invalid radix arguments,
checked against an independent syntax-validation-plus-Rust-parser oracle.
All nine focused numeric nextest tests passed for the final candidate (143 other
runtime tests were deliberately excluded). Source tests in [`source-tests.ms`](source-tests.ms)
passed in Debug and Release for the native-suffix candidate, covering every base
and public range/error identities. The final conservative candidate did **not**
receive a separate source-test execution before rejection; no such claim is made.

Independent read-only review found no correctness defect in the three candidates,
proved the final `u128` update is below `2^69`, and identified the long-error
controls, exact untimed cycle checks, input barriers and order/count refinements.
Those issues were resolved before the final two sessions. Independent evidence
review verified dataset identities, hashes, reported ratios, patch applicability,
and byte-identical production restoration.

Scoped Clippy with warnings denied passed for the native-suffix and conservative
candidates; formatting and repository checks passed for native-suffix and the
final evidence tree. Broad workspace execution, lifetime/ownership checks, backend/parity
investigations, and Windows/network work were outside this campaign lane.
Normal repository CI remains unchanged. Integrated-main replay is still needed
after campaign merges; these isolated, rejected experiments cannot establish it.

## Reproduce or audit

Use the pinned toolchain and normal repository build prerequisites. From separate
worktrees at the baseline, apply exactly one saved patch to the candidate, build
both native archives, and use one frozen compiler to build both copies of
`main.ms`. The current harness is the stronger protocol used for the last two
trials; the first trial's older sources are historical evidence only.

```sh
cargo xtask runtime
cargo build --release --locked -p ms-cli
cp measured-main.ms.txt /tmp/integer-parse-main.ms
MS_RT_LIB=/absolute/baseline/target/ms-native/libms_native.a \
  /absolute/frozen/ms build /tmp/integer-parse-main.ms --build-type Release -o before
MS_RT_LIB=/absolute/candidate/target/ms-native/libms_native.a \
  /absolute/frozen/ms build /tmp/integer-parse-main.ms --build-type Release -o after
cp before aa
python3 repeat.py ./before ./aa ./after ./rust-control --repeats 8 --count 300000 > paired.jsonl
python3 validate.py > /tmp/integer-parse-summary.md
diff -u summary.md /tmp/integer-parse-summary.md
```

`validate.py` checks every retained identity, oracle, sample count, phase/order,
A/A hash, timing bound and summary before emitting all tables. No existing test,
check, threshold or production source is changed by this evidence directory.
