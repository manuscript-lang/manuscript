[Wiki](../index.md) › [Runtime and stdlib](index.md)

# ChaCha and BLAKE2 stay in Manuscript

Decision (Chinmay, 2026-11-14): for now, do not add Rust natives or SIMD for ChaCha or BLAKE2. Keep them in stdlib `.ms` and improve the compiler or a general primitive if they are slow ([Manuscript first](../repository/standing-project-rules-from-the-owner.md)).

Apply when: speeding up `@std/crypto` ciphers or hashes.
Evidence: [perf-bash](../../skills/perf-bash/SKILL.md).
