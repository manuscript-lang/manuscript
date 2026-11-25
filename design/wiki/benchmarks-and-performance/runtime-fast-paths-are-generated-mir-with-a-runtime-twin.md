[Wiki](../index.md) › [Benchmarks and performance](index.md)

# Runtime fast paths are generated MIR with a runtime twin

Verified (2026-11-14, `bench/perf/rt-hot-retired/README.md`): the Rust `ms-rt-hot` helper bitcode is deleted. Every fast path is MIR that the emitter compiles, with the runtime function as the slow twin. Against `main`, map and set lookups, `String.view` and `StringBuilder.append` came out equal or faster, and the engineering suite output was byte-identical.

- Direction (Chinmay): no raw memory or byte primitives in Manuscript; the fast paths are shared MIR operations that the inliner folds, with no language change. See `design/proposals/retire-ms-rt-hot.md`.
- In C the passes are `compiler/opt/opt_strfast.c` (`parse_int`, `contains`, `compare`, `starts_with`, `ends_with`, scalar step and at), `opt_viewfast.c` (`String.view`, `String.slice`, `Bytes.view`), `opt_bytesfast.c` (fixed-width reads, byte search) and `opt_probe.c` (map and set probes, roles `MR_MAP_PROBE_*`). Lowering declares the runtime function with a role; each role gets one generated `inline(always)` function that decides the common case and calls the runtime only for the rest. Moving a runtime function into the runtime without its fast path is a perf regression: find such gaps with a callgrind per-function diff against `main`.
- A `String` key under 16 bytes is two words, so the MIR probe hashes those words with no branch on length; a longer key folds 8-byte words in a loop; equal-length flat keys of 16 to 32 bytes compare with overlapping word loads. A matching hash makes equal words decide a key and only distinct blocks call the runtime. Change the probe's hash and the runtime's hash together.
- A piece of up to fifteen bytes of an in-range, ASCII or scalar-aligned text becomes an inline string with no call; a longer piece, an out-of-range or negative bound or a mid-scalar bound calls the runtime. `Bytes.view` with `0 <= start < end <= len` is a stored `{ptr + start, end - start, 0}`; `Bytes ==` calls the byte compare, not the descriptor-driven slot compare (8.8% fewer instructions on `replace_each`).
- A map passed by address (`update`) is not a map value: the probe takes a pointer argument as the map itself. Storing that pointer into a slot and reading it as a map made `update` miss every key.
- Keep a selects-for-everything form out of hot paths: computing all three length cases of the hash plus a full word compare was 40 more instructions per lookup than branching on the common case.
- Test the ASCII case with the flag or the inline bits, never by scanning a short string (12% loss on `length`); build a substring searcher only for text of 128 bytes or more.
- A String-valued `Map` releases its values without descriptor dispatch, and `StrBuilder.freeze` keeps a small block whose size class already fits instead of calling `realloc` (issue #4021).
- Callgrind: small `Map` and builder allocations show as allocator calls; judge the small-object path by instruction counts of the whole program, not one row (issue #4021 chased this).


Apply when: moving a scan, compare, checksum or lookup between the runtime and generated MIR, or adding a runtime function with a hot common case.
Evidence: `src/compiler/opt/opt_strfast.c`, `opt_viewfast.c`, `opt_bytesfast.c`, `opt_probe.c`, [rt-hot-retired](https://github.com/manuscript-lang/manuscript/blob/48b25d38/bench/perf/rt-hot-retired/README.md).
Verify: a callgrind per-function instruction diff against `main` on the program that uses the path; `make conform`.
