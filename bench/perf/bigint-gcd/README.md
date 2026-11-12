# Public BigInt GCD

## 2026-11-12

The native GCD retains Euclid's algorithm, orders its initial magnitudes, avoids
copying equal/zero inputs unnecessarily, and reuses discarded dividend storage
in multiprecision division. Once the divisor fits `u64`, it computes the entry
remainder through the existing BigUint dispatch and finishes Euclid in `u64`.
The machine-integer boundary follows representability, not measured sizes.
Public results remain fresh nonnegative BigInts; GCD/LCM signatures, cancellation
entry checks and error contracts are unchanged.

### Revision, machine and method

Baseline: `979f7617494c4bc78fa6ed349cfb87012a671a57` (fresh `origin/main`). Candidate:
that revision plus this PR's GCD source diff. The repository's latest aggregate
[baseline](../baseline-2026-10-28.md) has no equivalent GCD cases and was measured
on another machine; its times are not used for a speedup claim.

Linux x86_64, Intel Xeon Platinum 8573C guest, five visible CPUs; subprocesses
pinned to CPU 0. Shared host: affinity does not remove host interference. Rust
1.99.1 and pinned num-bigint 0.5.1, repository release settings, no new dependency,
compiler flags, allocator changes or CPU-specific tuning. Both compilers rebuild
and embed their native runtime; application manifests report LLVM Release.

[main.ms](main.ms) parses immutable inputs and independent Python-integer expected
values outside the timer, alternates two operands, calls the public `gcd`, checks
every complete result, then destroys the result. Timings include the public
wrapper, allocation, equality validation and cleanup; they are not arithmetic-only.
Original cases alternate `a`/`a+1`; named zero/equal cases describe the first pair.
The five `unit_`/`exact_` cases repeat the same input to isolate one-step controls.
[Cases](cases.tsv) retain decimal operands, expected results and repetitions.

[The driver](../../tools/bigint_gcd.ms) alternates execution order, discards the
first pair and reports median paired candidate/baseline ratios. Raw final samples
and metadata live in [results-2026-11-12](results-2026-11-12/). Builds and setup
are excluded from the timer. No dynamic instruction count is claimed: `perf`
and `valgrind` were unavailable.

### Results

Median internal nanoseconds per operation; ratios are medians of paired ratios
and therefore need not equal ratios of the two independent medians.

| Case | Before ns/op | After ns/op | Paired after/before |
| --- | ---: | ---: | ---: |
| Small | 47.9 | 25.3 | 0.529 |
| Ordinary | 212.4 | 138.2 | 0.654 |
| Large | 60,493.9 | 53,410.4 | 0.876 |
| Negative | 3,965.6 | 3,251.9 | 0.786 |
| Zero | 17.8 | 17.6 | 0.995 |
| Equal | 70.0 | 62.0 | 0.897 |
| Unbalanced | 233.0 | 220.9 | 0.929 |
| Fibonacci | 44,202.7 | 36,085.1 | 0.817 |

All 13 added controls had median ratios below 1.0: zero-left 0.660, zero-right
0.916, reversed 0.913, divisors near 32/64-bit boundaries 0.788/0.875/0.874,
opposite-sign equality 0.766, both-negative 0.988, unit-divisor 0.989,
exact-small 0.819, exact-large 0.933, unit-left 0.955 and equal-one 0.676.

Twenty additional measured pairs (plus a discarded first pair) confirmed large
0.882, unbalanced 0.956 and zero-right 0.925. Both-negative was 0.997 and
unit-divisor 0.980: treat these as near-flat controls, not robust speedup claims.
Identical-baseline trials with the same 21-pair protocol gave median ratios
0.984–1.002 across those five controls. Individual paired ratios vary more;
all raw samples retain their order and ranges. No source candidate regression
was retained. These measurements do not establish a universal speedup.

The final timed runs had no concurrent builds or probes from this worker or
its supervising thread. Other activity outside the thread and shared-host
interference cannot be excluded.

### Alternatives and attribution

The initial isolated Rust comparisons tested magnitude Euclid, pinned binary GCD,
owned dividend reuse, an exact equal-bit-length quotient-one subtraction, and a
scalar Euclidean tail. Blanket binary GCD regressed small/ordinary/unbalanced
inputs despite large/Fibonacci wins. Quotient-one subtraction likewise regressed
small and ordinary controls. Neither was retained, and no empirical hybrid
threshold was added.

Owned dividend reuse alone improved long Euclidean chains but eagerly cloning
the retained divisor hurt equality. The first scalar-tail candidate improved the
original eight public cases, but added controls caught 1.316x for a 32-bit divisor,
1.086x reversed operands and 1.078x zero-left inputs. In num-bigint 0.5.1,
`&BigUint % u64` clones the dividend and computes a quotient; borrowed BigUint
remainder retains the remainder-only `u32` specialization. Preserving that dispatch
and normalizing operand order removed those regressions.

These source paths and ablations support storage reuse and scalar-tail work
reduction together. They do not isolate allocator or instruction-count savings,
or explain the entire earlier GMP gap. GMP may use tuned assembly; this patch
makes no compiler/backend attribution or universal library ranking.

### Correctness and reproduction

The Rust boundary test derives exact GCD/LCM from consecutive cofactors and checks
signs, equality, zero and 32/64-bit transitions. The called
[public fixture](../../../tests/conformance/fixtures/e2e/stdlib/bigint-gcd.ms)
covers the same contract through BigInt methods. Independent skeptical review
also ran 344 Python-oracle processes / 688 complete-result checks against the
candidate, with boundary and seeded random inputs.

Build each revision in a separate checkout using `cargo xtask runtime`, then
`cargo build --release --locked -p ms-cli`. Compile the same `main.ms` with each
compiler:

```sh
/path/to/before-ms build bench/perf/bigint-gcd/main.ms --build-type Release -o /tmp/gcd-before
/path/to/after-ms build bench/perf/bigint-gcd/main.ms --build-type Release -o /tmp/gcd-after
MS_CACHE=off target/release/ms run bench/tools/bigint_gcd.ms -- /tmp/gcd-before /tmp/gcd-after 11
```

Use 21 pairs and a final case name for a longer focused comparison. Pass the same
binary twice for an A/A control. The driver uses Linux `taskset`; production code
and correctness tests are portable. Checks and final source/binary hashes are
recorded with the raw results. No performance claim is based on build duration.

Local validation: 40/40 native tests under nextest; all seven BigInt conformance
fixtures; workspace `cargo fmt --all --check` and
`cargo clippy --workspace --all-targets -- -D warnings`; repository checks;
benchmark source checks and runner smoke/error controls. Full workspace nextest,
the full conformance corpus, and final exact-head CI remain merge gates.
