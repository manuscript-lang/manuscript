[Wiki](../index.md) › [Benchmarks and performance](index.md)

# A crypto dependency needs its fast feature checked with callgrind

Verified (Rust era, 2026-11-16, `bench/perf/crypto-signatures`): trimming a crate's default features silently dropped its fast path. Ed25519 built without precomputed tables ran a variable-base multiplication (100 µs a signature against Go's 37 µs; 525 to 290 ms for 3000 rounds once restored), and the regex crate built without `std` used a full-DFA fallback (1035M instructions against 442M). The lesson outlived the crates: a primitive can be correct and several times slower because a build option picked the generic path.

The C build vendors OpenSSL, zlib, PCRE2 and others (`src/third_party`, pinned by `c-libs.lock`). When adding or trimming a vendored library or its build options, profile one call with callgrind and look for a generic fallback (`variable_base`, `soft`, a portable field multiply) where a table or instruction-set path should run. Under `valgrind` OpenSSL's SHA and AES report the software path (no SHA-NI emulation), so instruction counts mislead for hashing; time those with wall clock against Go.

Apply when: changing build options of a vendored library, or adding a primitive.
Evidence: `bench/perf/crypto-signatures`, `src/third_party/c-libs.lock`.
Verify: callgrind on one call shows no generic fallback; wall clock is within Go's.
