# String append against Rust

`StringBuilder.append` against Rust's `String::push_str` (glibc, `rustc -C opt-level=3`), building about 1 MB from pieces of 4 B to 8 KiB. Manuscript is the default Release build (LLVM). `MS=ms sh bench/perf/strappend/run.sh 5` prints the best of N runs (each the best of 40 builds) in microseconds. It also builds `List[Int]`s of 10K to 1M items with `append` in a `while` loop against `Vec::push`. The `Platform benchmarks` workflow (run it by hand on a branch) runs the allocator tests and this table on Linux, macOS and Windows.

## 2026-10-30 (Linux): owned builders

Same machine as 2026-10-27, release build of this branch against `main` (b7ee9710), `run.sh 7` twice, back to back. `StringBuilder` is an owned byte buffer with a consuming `build()` instead of a shared handle, so an append no longer loads a sealed flag or goes through the shared cell. Microseconds, Manuscript only; Rust is unchanged at 25-77 us for these sizes.

| piece | main | owned builder |
|---|---|---|
| 4 B | 759-766 | 721-730 |
| 16 B | 147-152 | 142-149 |
| 64 B | 63-64 | 58-60 |
| 256 B | 31-32 | 30 |

Parity or better at every size; differences under about 10% are noise. The first run of the branch showed 16 B at 189 us because `build()` copied the buffer; it now moves it.

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

### After inlining the in-place append

Same workflow, after a non-inline string that fits the buffer is appended with a capacity check, one `memcpy` and a length bump in the caller (no runtime call), and the runtime's own append ends in a tail call to `memcpy`.

| piece / items | linux-amd64 | darwin-arm64 | darwin-amd64 | windows-amd64 |
|---|---|---|---|---|
| 4 B | 0.76x | 0.99x | 0.82x | 0.76x |
| 16 B | 0.69x | 1.00x | 0.62x | 0.31x |
| 64 B | 1.00x | 1.17x | 0.32x | 0.27x |
| 256 B | 1.38x | 1.00x | 0.12x | 0.09x |
| 1 KiB | 1.19x | 1.00x | 0.08x | 0.08x |
| 8 KiB | 0.06x | 0.93x | 0.07x | 0.08x |
| 10K items | 0.30x | 0.89x | 0.21x | 0.60x |
| 100K items | 0.32x | 0.55x | 0.11x | 0.23x |
| 1M items | 0.30x | 0.28x | 0.11x | 0.17x |

The Linux runner (AMD EPYC 7763) is still behind at 256 B (1.38x) and 1 KiB (1.19x), and macOS arm64 at 64 B (1.17x); everything else is at or ahead of Rust.

### After dispatching `memcpy` to an AVX2 body

`memcpy` jumps through a pointer set on first use to an AVX2 body (128-byte blocks) or an SSE one, instead of a four-level call chain with its own frame: a 256 B copy drops from 65 to 38 instructions (Rust with glibc: 32). Only Linux x86_64 uses it; macOS and Windows already call their system `memcpy`. Runner noise is 10-20%, so Linux's 1.02-1.19x and arm64's 1.11-1.26x are within a run or two of each other.

| piece / items | linux-amd64 | darwin-arm64 | darwin-amd64 | windows-amd64 |
|---|---|---|---|---|
| 4 B | 0.79x | 0.96x | 0.81x | 0.68x |
| 16 B | 0.65x | 1.00x | 0.62x | 0.39x |
| 64 B | 1.02x | 1.26x | 0.32x | 0.22x |
| 256 B | 1.19x | 1.11x | 0.12x | 0.09x |
| 1 KiB | 1.10x | 1.07x | 0.08x | 0.06x |
| 8 KiB | 0.07x | 0.93x | 0.07x | 0.05x |
| 10K items | 0.33x | 1.00x | 0.21x | 0.56x |
| 100K items | 0.32x | 0.57x | 0.10x | 0.24x |
| 1M items | 0.30x | 0.39x | 0.09x | 0.16x |
