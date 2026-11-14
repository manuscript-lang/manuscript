[Wiki](../index.md) › [Benchmarks and performance](index.md)

# Runtime string results are built in place, not through a `Vec`

Verified (2026-11-14, `bench/perf/string-pass/README.md`): `from_buf(vec)` allocates a `Vec`, copies it into a runtime string and frees the `Vec`, so an operation whose result length is known writes straight into its result with `build_exact` (inline when 15 bytes or fewer, else one allocation). `lower` of a 55-byte path went from 40 to 22 ms per million (Rust 26), `reverse` from 66 to 14 (Rust 52).

- `starts_with` and `ends_with` are inline MIR in `ms-lower/src/rtstr.rs` for an affix of up to 16 bytes (two overlapping loads; three byte reads under four bytes); a longer affix calls `memcmp` through the runtime twin. Call plus `memcmp` was 58 instructions per test, inline is 6.
- A result known to be ASCII carries the flag (`with_ascii`), so a later `length()` or index is O(1); `replace` that shrinks kept no flag and scanned 1.5 MB per `length()` call.
- `parse_float` has an exact fast path (mantissa up to 2^53, power of ten within 22); everything else, valid or not, still goes to the general parser. The remaining float cost is the shortest-digits search in `shortest`, which formats through `{:e}` and reparses.

Apply when: adding or tuning a runtime string operation, or seeing `malloc`/`memmove` under a string call in callgrind.
Verify: `bench/perf/string-pass` and `string-micro`, callgrind instruction counts of one kernel before and after.
