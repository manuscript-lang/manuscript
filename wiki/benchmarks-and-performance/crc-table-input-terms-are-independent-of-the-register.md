[Wiki](../index.md) › [Benchmarks and performance](index.md)

# CRC table input terms are independent of the register

Verified on the measured x86-64 build: in slicing-by-eight IEEE CRC32, the four
upper input-byte table terms do not depend on the previous CRC register. Combining
them before the register-dependent terms shortened the carried XOR chain in the
native disassembly and improved compiled whole-input calls by about 25%.

Apply when: changing the shared checksum primitive. Source order alone does not
constrain the optimizer; confirm native assembly and tiny/tail/seeded controls.
Evidence: [same-algorithm C, paired MS and A/A measurements](../../bench/perf/checksum-dependency/README.md).
Verify: unchanged bitwise-oracle/continuation tests and explicit little-endian
loads; retain all UInt32 seeds and empty-update identity.
