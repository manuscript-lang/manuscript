# Image rotations

Measures compiled `Image.rotate180` and `rotate270` against their previous
compositions: horizontal then vertical flip, and 90 degrees then those two flips.
The reference compositions and the current public methods run in the same native
executable. This measures image operations, not compilation, caches, codecs or I/O.

## Reproduce

Build the repository compiler and runtime using the contributor instructions, then:

```sh
target/release/ms build bench/perf/image-rotations/main.ms --build-type Release -o /tmp/image-rotations
python3 bench/perf/image-rotations/run.py /tmp/image-rotations /tmp/image-rotations.json
```

Python uses only its standard library and Linux `taskset`. Where the default
artifact directory is not writable, the compiler supports `XDG_CACHE_HOME`.
The driver selects an allowed CPU and alternates variant order for seven fresh
processes per case. Input generation, full-byte comparison and one warm call are
outside the timer. Function selection also happens outside the timer; every
variant uses the same function-value invocation loop and sampled-byte checksum.
Each result allocation and destruction is timed. There is no cache flushing.

Correctness checks compare every byte and dimensions for all four channel modes
over 100 small shapes, then check inverse identities. Every timed shape also gets
a full-byte comparison outside its timer. Sixteen malformed baseline/current
pairs compare exit status, successful output and the first fault-message line:
zero/negative dimensions, short/extra/non-channel-aligned buffers and bounded
overflow cases. The opposite extreme zero-dimension pairs take Int.max empty-loop
iterations in the baseline; they are intentionally not run by this bounded driver.

## 2026-11-12

Reference source: main `37a14ba5797bed73a66d1350bee03d2238c63a20`.
Linux x86_64, AMD EPYC 7763, Rust 1.99.1, release compiler and LLVM Release
programs. Raw samples, binary SHA-256, selected CPU and environment are in
[`results-2026-11-12`](results-2026-11-12/). The existing dated stdlib baseline
does not include these rotation cases; this is a new focused suite, not a claim
about the overall stdlib benchmark. No hardware instruction counters were
available. Shared-machine timing remains subject to scheduling and code-layout
variation; no samples were removed.

Median nanoseconds per rotation, seven samples per cell:

| Shape / channels | 180 previous | 180 current | 270 previous | 270 current |
| --- | ---: | ---: | ---: | ---: |
| 1×1 RGBA | 36.38 | 17.98 | 47.48 | 17.32 |
| 3×2 RGBA | 73.51 | 41.20 | 118.44 | 42.84 |
| 64×48 RGBA | 21,952 | 12,479 | 36,207 | 13,305 |
| 256×192 RGBA | 351,514 | 194,219 | 569,810 | 203,579 |
| 1024×768 RGBA | 5,556,949 | 3,028,688 | 10,168,260 | 3,864,276 |
| 64×48 Gray | 8,068 | 5,564 | 13,736 | 5,298 |
| 64×48 GrayAlpha | 12,657 | 8,363 | 21,817 | 7,987 |
| 64×48 RGB | 17,351 | 10,273 | 29,427 | 10,543 |

The unchanged 90-degree rotation is recorded in every sample matrix. A preliminary
cross-binary comparison showed noisy Gray control timings, so an additional
alternating, eleven-sample comparison used longer batches. Its current/reference
medians range from 0.995 to 1.012 across the same eight shape/mode cases; all raw
outputs are in `control90.json`. This control used the original scratch prototype
binary and the integrated binary, so it is a stability check rather than an exact
whole-program before/after comparison. The primary paired measurements above use
identical harness code in one executable. Run no builds or tests concurrently
with the timed driver.

The native conformance fixture `e2e/stdlib/image-rotations` additionally checks
output storage independence. Existing image and image-fuzz fixtures pass. The new
fixture passes with LLVM and Cranelift. Direct rotations preserve malformed-shape
behavior through the original compositions; they do not change the public API.
