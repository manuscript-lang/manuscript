# String append against Rust

`StringBuilder.append` against Rust's `String::push_str` (glibc, `rustc -C opt-level=3`), building about 1 MB from pieces of 4 B to 8 KiB. Manuscript is the default Release build (LLVM). `MS=ms sh bench/perf/strappend/run.sh 5` prints the best of N runs (each the best of 40 builds) in microseconds.

## 2026-10-27

Linux x86-64, Intel Xeon 2.1 GHz (virtualized), rustc 1.99.1, median of two sets of 5 and 9 runs; differences under about 10% are noise. Ratio is Manuscript over Rust.

| piece | before | after |
|---|---|---|
| 4 B | 1.05x | 0.92x |
| 16 B | 1.6-1.8x | 1.04-1.11x |
| 64 B | 2.3-2.6x | 0.94-1.06x |
| 256 B | 4.3-4.8x | 1.12-1.26x |
| 1 KiB | 5.4-5.6x | 0.88-0.92x |
| 8 KiB | 5.4x | 0.96x |

What changed: `build()` on a builder that is not used again moves its bytes instead of copying them (`buildmove`); a buffer that grows past 32 KiB moves once into a per-isolate growth region and then extends in place, like glibc's `realloc` at the top of the heap; copies of 65 B to 2 KiB use vector blocks instead of `rep movsb`.
