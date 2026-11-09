# Multipart streaming, 2026-11-09

Baseline: `f2cc2461827314f6aba6a823c15a92546d70933d`. Candidate MIME source blob: `449b4a5632bdad1682b015929d97e0ecb0416907` (local measurement snapshot `d62864e541ffb1daa78c7d6ccc1bf9bec7d0b3b2`; issue [#3264](https://github.com/manuscript-lang/manuscript/issues/3264)). Linux x86-64 shared worker, AMD EPYC 9V74, kernel 6.18.57, Rust 1.99.1. The [latest dated baseline](../../baseline-2026-10-28.md) is suite context, not a numerical cross-host comparison.

## Protocol

Both compiler binaries were built from the same Rust sources with `CARGO_PROFILE_RELEASE_DEBUG=0` and one Cargo job, after debug-info builds exhausted this worker's memory. Each embeds the corresponding standard library, the same freshly built host glibc runtime, and the unchanged hot runtime helper IR. Generated programs use normal Release settings, once with LLVM and once with `MS_BACKEND=cranelift`. Static/musl execution is not covered here.

The same source calls the public `multipart_parts(from_bytes(...))` API. Input construction is outside the timer; each operation includes the owned input-body copy. Every run checks the returned part count, body sizes, a payload byte, and an exact total returned-byte count. `MS_THREADS=1` for both binaries. Seven alternating process pairs per case follow one warmup process per binary. Each process repeats the same case: twice for 1 MiB/1 KiB, once for 4 and 8 MiB/1 KiB, three times for 4 MiB/64 KiB, 100,000 times for the 128-byte control, 5,000 times for the 64 KiB control, and 1,000 times for 100 small parts.

The reusable [benchmark cases](../mime_bench.ms) cover both fragmented sizes, the default 64 KiB source chunks, neighboring small/single-chunk/many-part controls, and limit rejection. Run `ms bench bench/perf/stdlib/mime_bench.ms --json --samples 7`; use an explicit baseline and candidate compiler and alternate their order. Raw samples, workload source, binary hashes, build logs and provenance stay outside the repository.

## Results

Medians per multipart stream:

| Workload | LLVM before | LLVM after | Cranelift before | Cranelift after |
| --- | ---: | ---: | ---: | ---: |
| 1 MiB part, 1 KiB chunks | 44.155 ms | 1.336 ms | 44.757 ms | 1.299 ms |
| 4 MiB part, 1 KiB chunks | 748.495 ms | 5.237 ms | 708.001 ms | 5.651 ms |
| 8 MiB part, 1 KiB chunks | 3423.754 ms | 12.536 ms | 3529.975 ms | 12.223 ms |
| 4 MiB part, default 64 KiB chunks | 26.216 ms | 4.600 ms | 26.287 ms | 4.514 ms |
| 128-byte part, one chunk | 1.615 us | 1.562 us | 2.056 us | 2.038 us |
| 64 KiB part, one chunk | 14.848 us | 13.759 us | 15.761 us | 13.478 us |
| 100 parts of 128 bytes, one chunk | 134.650 us | 127.798 us | 164.586 us | 155.207 us |

A separate LLVM limit-rejection control used a 64 KiB body in 1 KiB chunks with a 4096-byte raw-part budget. Three alternating process pairs, each with seven calibrated 25 ms samples, returned the expected `EOVERFLOW`: 3133 ns to 2978 ns per operation.

No control regressed in these trials; the smallest differences should be treated as noise rather than universal speedup claims. For the LLVM 8 MiB case, median whole-process minor faults fell from 57,125 to 14,631. Those fault counts include startup and untimed input construction, unlike the operation timer. Callgrind/instruction counts were unavailable on this worker.

The source explains the large gain: the old implementation concatenates and searches the entire growing part on every transport chunk. The candidate appends confirmed bytes to a builder and searches only the delimiter-overlap tail plus new input. Increasing part size no longer causes the previous prefix to be copied and scanned again for every chunk. Many parts within one giant transport chunk are a separate, unchanged workload dimension.
