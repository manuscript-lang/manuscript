[Wiki](../index.md) › [Standard-library design](index.md)

# Calls that fail only on a programmer's constant return plain values; fixed-width codecs are methods

Decision: `String.pad_start/pad_end` and `Float.to_fixed/to_precision/to_exponential` return `String`. Their only failures were a negative budget or a digit count outside 0..100, always a literal in the caller, so every table printed `.get()`. A short target or empty padding returns the text unchanged, there is no byte budget (`repeat` keeps one because it multiplies), output beyond the string limit faults like `concat`, and a digit count out of range faults.

Apply when: giving a native a `Result` whose error comes only from a constant argument, or adding a sized-number codec.
Evidence: [text-padding fixture](../../tests/e2e/testdata/stdlib/text-padding.ms), [binary fixture](../../tests/conformance/fixtures/e2e/stdlib/binary.ms), `bytes.read_int32_le` and `bytes.append_int32_le` in `bench/perf/stdlib/binary_bench.ms`.
Verify: `ms test tests/conformance/fixtures/e2e/stdlib/binary.ms tests/e2e/testdata/stdlib/text-padding.ms`; `make stdlib-bench BENCHFILTER=bytes.`.
