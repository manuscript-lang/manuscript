# String append against Rust

`StringBuilder.append` against Rust's `String::push_str` (glibc, `rustc -C opt-level=3`), building about 1 MB from pieces of 4 B to 8 KiB. Manuscript is the default Release build (LLVM). `MS=ms sh bench/perf/strappend/run.sh 5` prints the best of N runs (each the best of 40 builds) in microseconds. It also builds `List[Int]`s of 10K to 1M items with `append` in a `while` loop against `Vec::push`. The `Platform benchmarks` workflow (run it by hand on a branch) runs the allocator tests and this table on Linux, macOS and Windows.

## 2026-10-27 (Linux)

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

## 2026-10-27 (GitHub-hosted runners)

`.github/workflows/bench-platforms.yml`, one run per platform on shared runners, so expect noise of 10-30%. `ms-rt` unit tests (allocator growth region included) passed on all four. Ratio is Manuscript over Rust (MSVC on Windows, system allocator on macOS).

| piece / items | linux-amd64 | darwin-arm64 | darwin-amd64 | windows-amd64 |
|---|---|---|---|---|
| 4 B | 0.92x | 0.64x | 0.30x | 0.69x |
| 16 B | 0.83x | 0.78x | 0.32x | 0.31x |
| 64 B | 1.58x | 1.38x | 0.93x | 0.26x |
| 256 B | 1.80x | 1.32x | 0.70x | 0.08x |
| 1 KiB | 1.38x | 1.07x | 0.48x | 0.06x |
| 8 KiB | 0.60x | 1.00x | 0.43x | 0.04x |
| 10K items | 0.25x | 1.14x | 0.50x | 0.50x |
| 100K items | 0.33x | 0.58x | 0.53x | 0.13x |
| 1M items | 0.33x | 0.39x | 0.19x | 0.08x |

Windows and macOS are ahead of Rust because their system allocators are slower than glibc's at growing a buffer. On the Linux runner and macOS arm64, 64 B to 1 KiB pieces are 1.3-1.8x behind while the local machine above is within 1.1x. Rust's time for those sizes drops by a third on the runner and ours does not, so what remains looks like per-append call cost (the runtime call and string decode against an inlined `push_str`), not growth.
