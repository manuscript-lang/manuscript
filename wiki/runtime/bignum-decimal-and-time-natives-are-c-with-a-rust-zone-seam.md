[Wiki](../index.md) › [Runtime](index.md)

# BigInt, Decimal and time natives are C; zones live in Manuscript

Verified: `runtime/std/bignum.c` (a thin layer on OpenSSL `BIGNUM`, already linked for crypto; Chinmay, 2026-11-20: no hand-rolled bignum), `bigint.c`, `decimal.c` and `time*.c` replace the Rust crates. `ms-decimal` is deleted; `ms-lower/src/decimal_literal.rs` only parses a literal into the stored coefficient and exponent. The time natives take an offset and a zone name; zones resolve in `stdlib/internal/zone.ms` ([zones](time-zones-are-bundled-tzif-read-by-manuscript.md)), so the C has no zone seam.

- Oracles, not hand checks: `runtime/tests/oracle/*_gen.py` write exact Python integers and `decimal` answers, and `time_golden.txt` is Go's `time` (UTC and fixed offsets only; named zones run in conformance). A positive-only fuzz missed a sign bug in the divide-and-conquer `to_string`; the oracle's negative cases caught it.
- BN adds only what BIGNUM lacks: floor shifts, two's complement and/or/xor on negatives, integer sqrt, correctly rounded `to_double`, 128-bit and int64 conversion, text in any radix, and a power-of-two `pow` (BN_exp on 2^(2^24) takes over a minute).
- Decimal speed: add, subtract, multiply and round stay in 128-bit arithmetic (`round_wide`, `combine_wide`, `rounded_magnitude`; a coefficient is below 2^113) and fall to the bignum only when the aligned sum or product exceeds 128 bits, and divide always uses it. That took `decimal.add_round` from 377 to 65 ns/op (2026-11-20, `bench/perf/stdlib/numbers_bench.ms`); before it, pooled BIGNUMs and a shared `BN_CTX` had taken the benchmark from 13.8 s to 4.2 s against Rust's 3.4 s. Profile with `valgrind --tool=callgrind` before adding more.
- Huge values are slower than the retired hand-written code: `3^1000000` 0.25 s against 0.03 s, a 120k-digit `to_string` 0.21 s against 0.08 s (OpenSSL's `BN_exp` and radix conversion are not asymptotically fast).
- A C fault needs frame pointers for the stack line fixtures expect: `cargo xtask runtime` passes `-fno-omit-frame-pointer`.
- Every std test links all of `runtime/std/*.c`, so a new cross-file seam needs stubs like `runtime/tests/fake_list.h`.

Apply when: changing bignum, Decimal or time natives, or porting the zone database.
Evidence: [bignum.h](../../runtime/std/bignum.h), [decimal.c](../../runtime/std/decimal.c), [time.c](../../runtime/std/time.c), [oracle](../../runtime/tests/oracle/).
Verify: `make c-test` passes (about 7,000 oracle cases) and `make conform` is unchanged.
- BN failures: `must` raises an overflow fault for OpenSSL's size cap (`BN_R_BIGNUM_TOO_LONG`, about 2^29 bits) and the out-of-memory fault otherwise. `BN_gcd` is constant-time and slow on wide values, so `ms_big_gcd` runs Euclid with `BN_mod`. Not done: the thread pool keeps the capacity of a BIGNUM that held a huge intermediate and ended small (up to 16 per thread).
