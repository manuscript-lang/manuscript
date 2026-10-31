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
