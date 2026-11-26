[Wiki](../index.md) › [Benchmarks and performance](index.md)

# A guard on `x + c` bounds `x`, so fixed-size blocks need no checks

Verified (2026-11-12): `while i + 32 <= n { ... }` with an inner `for j in 0..32` reading `b.get(i + j, none)` kept a bounds check on every read, because the range pass recorded the guard on `i + 32` and nothing connected it to `i`. A checked read branches to a second load, so LLVM would not vectorize the block. `prove_le` now derives `x <= b - c` from a relation on `x + c`. Blocked memchr went from 730 to 31 us per MB and blocked equality from 1,027 to 36 us (native: 12 and 44).

- Write byte scans as a counted block with no early exit inside, an early exit between blocks, and a scalar tail. A block loop vectorizes; an early-exit byte loop does not (29x behind native `memchr`).
- `Bytes.int64_le` and the other fixed-width readers inline now (generated MIR in `src/compiler/opt/opt_bytesfast.c`; `msrt_bytes_read_word` remains the fallback twin). Check the LLVM IR (`ms build --emit mir`) for a remaining `call` and `declare`.

Apply when: moving a scan, compare or checksum from the runtime into `.ms`.
Evidence: [results](https://github.com/manuscript-lang/manuscript/blob/48b25d38/bench/perf/native-fallbacks/README.md), range pass, fixture.
Verify: `MS_EMIT_OPT=1 ms build --emit mir` shows `list.get.u` in the block and no `list.get.nn`; `gaps.ms` blocked cases within 3x of native.
