[Wiki](../index.md) › [Benchmarks and performance](index.md)

# A split of a short record scans words once and sizes its list once

Verified (2026-11-14, `bench/perf/suite/pargroup`, 400k log lines of 8 fields): `String.split` started a list for four pieces and searched once per piece. Room for eight (bounded by the text) took 940M to 780M instructions; scanning an at most 128-byte text for a one-byte separator in eight-byte words took a further 873M to 803M (current main). The same scan up to 512 bytes made sparse and long-text controls 9% worse, so the limit stays at 128.

Rejected for now: a `split` read only by constant indexes without building the list. Each piece costs about 90 instructions, but every index would repeat its searches, so the estimated saving is under 15% on this program.

Apply when: changing `split_into` in `crates/ms-rt/src/string.rs`. Measure `valgrind --tool=callgrind` totals for a record, a two-field text, a sparse 450-byte text and a long text together.
