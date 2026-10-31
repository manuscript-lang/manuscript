[Wiki](../index.md) › [Benchmarks and performance](index.md)

# Shared collection helpers need conversion and union controls

Verified (2026-10-29): eliminating a redundant lookup in `List.distinct` reduced
instructions but common-case wall timings remained inconsistent; the List change
was not retained. A shared copy-helper refactor also added roughly five
instructions per new key to List-to-Set conversion. Keep union and conversion
as controls when changing a Set helper, and distinguish fewer hash calls from a
wall-clock claim. The retained Set-only change skips a check only when one
input's uniqueness proves that a fresh output cannot already contain the key.

Apply when: changing a shared collection lookup or copy helper.
Evidence: [collection-copy measurements and rejected variants](../../bench/perf/list-distinct/README.md).
Verify: paired unique/duplicate and small/large workloads, exact producer status
and checksums, whole-producer instruction counts, and the Set hash-count regression.

Verified (2026-10-29, BitSet predicates): Boolean relation queries previously
built a full temporary algebra result before checking emptiness. Direct word
comparisons preserve arbitrary exposed word arrays and allow early exit. Keep
the algebra methods' representations intact: shortening their output can change
observable `words`, even when set membership is unchanged. The
[BitSet report](../../bench/perf/bitset-relations/README.md) records full-scan,
early-answer and empty/small controls; the source fixture compares against the
unchanged algebra across unequal lengths, trailing zeros and signed high bits.

---
Topics: [Cleanup and resources](../topics/cleanup-and-resources.md)
