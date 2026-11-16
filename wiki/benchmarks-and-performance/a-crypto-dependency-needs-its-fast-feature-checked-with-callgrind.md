[Wiki](../index.md) › [Benchmarks and performance](index.md)

# A crypto dependency needs its fast feature checked with callgrind

Verified (2026-11-16, `bench/perf/ed25519`): `ed25519-dalek` was built with `default-features = false`, which dropped `fast` (`curve25519-dalek/precomputed-tables`). `sign` and `public_key` then ran a variable-base multiplication: 100 µs a signature against Go's 37 µs, 46% of the profile in the AVX2 field multiply. With `fast`, 3000 rounds of public key, sign and verify went 525 to 290 ms (Go 280 to 330 ms) for about 12 KB of linked size in programs that use Ed25519.

Under `valgrind` the `sha2` and AES crates report the software path (no SHA-NI emulation), so instruction counts mislead for hashing; time those with wall clock against Go.

Apply when: trimming default features from a crate in `crates/ms-std-*`, or adding a primitive: profile one call with callgrind and look for a generic fallback (`variable_base`, `soft`) where a table or instruction-set path should run.
