[Wiki](../index.md) › [Benchmarks and performance](index.md)

# Numeric parsing needs invalid-input performance controls

Verified (2026-10-31): three integer-radix parsing candidates improved valid inputs
but regressed error controls and were rejected. A sticky-overflow implementation
continued arithmetic after the value was already out of range, slowing long
overflow/late-invalid strings 2.4–3.4×. Syntax-only suffix fallbacks still regressed
early-invalid and late-invalid decimal cases. Successful parsing alone cannot
establish a safe optimization.

Apply when: merging numeric validation and conversion scans or changing range checks.
Evidence: [rejected parsing trials, raw samples and patches](../../bench/perf/integer-parse-radix/README.md).
Verify: preserve `InvalidData` precedence after an overflowing prefix; measure short
and long overflow, early/late invalid bytes, leading-zero success, all signs and
bases, and unchanged formatting controls with balanced A/A. An equivalent Rust
error baseline must validate the complete syntax; `from_str_radix` alone can stop
earlier at overflow. Put an input optimization barrier inside invariant Rust loops.

A later [Float ASCII-scan trial](../../bench/perf/float-parse-ascii/README.md)
proved that the grammar check already guaranteed UTF-8 validity. Removing the
redundant scan improved valid parsing 13–18%, but short invalid/Unicode rejection
slowed about 9–10% in a longer balanced confirmation. An unchanged integer control
also regressed. Same-location rebuilds produced byte-identical benchmark programs,
so build location did not explain the results. The candidate was rejected and the
checked conversion restored. Safety proofs and successful-input gains do not
replace complete affected controls; retain negative measurements and stop when
a confirmed regression remains unexplained.
