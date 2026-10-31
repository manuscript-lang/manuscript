[Wiki](../index.md) › [Benchmarks and performance](index.md)

# Shared collection helpers need conversion and union controls

Verified (2026-10-29): eliminating a redundant lookup in `List.distinct` reduced
instructions but common-case wall timings remained inconsistent; the List change
was not retained. A shared copy-helper refactor also added roughly five
instructions per new key to List-to-Set conversion. Keep union and conversion
as controls when changing a Set helper, and distinguish fewer hash calls from a
wall-clock claim.

Apply when: changing a shared collection lookup or copy helper.
Evidence: [collection-copy measurements and rejected variants](../../bench/perf/list-distinct/README.md).
Verify: paired unique/duplicate and small/large workloads, exact producer status and checksums, whole-producer instruction counts, and the Set hash-count regression.
