# Hex and padded Base64 encoding against C

The encoding change builds hexadecimal ASCII in reserved byte-list batches of at most 16KiB, converts each batch, and appends it to the result. Padded Base64 reuses the existing unpadded encoder and adds only the canonical suffix. Public signatures, alphabets, tails and decoder behavior remain unchanged.

## Current-main confirmation

The [current-main follow-up](current-main-2026-11-12/README.md) rebuilds baseline and proposed against main `15e35bc8a`, using identical typed setup helpers that compile normally with all checks enabled. It repeats all 31 cases with seven paired runs, A/A, RSS and correctness controls. All case medians improve. The earlier results below remain historical; their original fixture and source hashes are preserved in the PR history.

## Historical 2026-11-12 comparison

Baseline main: `0ff39fa82b0df7239b9ba8157c03d64ce165d541`. Actual public library calls compiled with Manuscript 0.1.0 LLVM Release on an AMD EPYC 9V74 Linux x86_64 VM. The proposed stdlib source hash and application executable identities are in [metadata](results-2026-11-12/metadata.json).

C is GCC 14.2.0, `-O3 -march=x86-64-v3 -mtune=generic`, no LTO, with separate operation/driver translation units. `C-exact` allocates the known output size; `C-grow` uses checked geometric output growth. Both allocate and free a fresh output per operation and perform the same complete output comparison as Manuscript. The exact-capacity C baseline is not silently compared as though it had the builder's growth costs. Empty immutable strings and C allocated empty buffers retain their implementation differences; empty-case results do not establish C parity.

Inputs and Python-generated expected outputs are loaded outside timing. All outputs are compared completely and checksums consumed. Every child warms up for 10% of its measured count. Equal counts for all four variants are calibrated to at least 20ms for the fastest, capped at 10 million. Eleven alternating paired runs, pinned to CPU4, no concurrent builds and no removed outliers. Times include allocation, output validation and cleanup; they exclude startup, input generation, file reads and reporting. This is API throughput, not an isolated compiler-loop comparison.

The table reports median ns/call; the ratio is the median of **paired proposed/baseline ratios**, followed by their full range. Size suffixes are input bytes. All measured case medians improve, but nonempty outputs still trail optimized C. No universal C-parity or memory-reduction claim is made. The temporary ASCII batch is bounded; input materialization and final output storage remain.

| Case | Baseline ns | Proposed ns | C exact ns | C grow ns | Paired ratio | Range |
|---|---:|---:|---:|---:|---:|---:|
| hex-random-0 | 32.44 | 5.76 | 13.55 | 14.12 | 0.179 | 0.168–0.190 |
| b64-random-0 | 33.52 | 5.48 | 13.80 | 14.06 | 0.160 | 0.136–0.189 |
| hex-random-1 | 64.35 | 48.01 | 13.80 | 15.70 | 0.737 | 0.689–1.011 |
| b64-random-1 | 83.87 | 34.22 | 14.54 | 17.00 | 0.402 | 0.378–0.491 |
| hex-random-2 | 68.28 | 52.19 | 14.12 | 16.42 | 0.755 | 0.702–0.914 |
| b64-random-2 | 86.00 | 36.89 | 15.10 | 17.52 | 0.426 | 0.394–0.451 |
| hex-random-3 | 91.42 | 52.46 | 14.55 | 17.26 | 0.574 | 0.549–0.622 |
| b64-random-3 | 92.82 | 28.32 | 15.02 | 17.12 | 0.312 | 0.278–0.337 |
| hex-random-13 | 162.95 | 77.37 | 20.23 | 43.27 | 0.475 | 0.279–0.541 |
| b64-random-13 | 187.00 | 75.94 | 20.75 | 40.95 | 0.417 | 0.365–0.467 |
| hex-random-64 | 467.84 | 164.57 | 56.88 | 164.19 | 0.369 | 0.248–0.393 |
| b64-random-64 | 365.29 | 211.67 | 52.43 | 137.58 | 0.574 | 0.523–0.584 |
| hex-random-1024 | 4872.38 | 1933.02 | 785.31 | 1082.60 | 0.392 | 0.375–0.402 |
| b64-random-1024 | 3265.25 | 2726.39 | 651.53 | 1044.13 | 0.835 | 0.727–0.899 |
| hex-random-65536 | 306365.98 | 129165.32 | 46701.69 | 59382.00 | 0.419 | 0.387–0.516 |
| b64-random-65536 | 192584.80 | 175147.00 | 40263.75 | 57115.90 | 0.891 | 0.854–0.945 |
| hex-random-1048576 | 5082151.39 | 2101267.86 | 789824.24 | 963008.22 | 0.413 | 0.195–0.433 |
| b64-random-1048576 | 3201164.72 | 2818237.70 | 644341.91 | 908303.68 | 0.898 | 0.826–0.993 |
| hex-zeros-65536 | 306383.98 | 127059.61 | 47407.75 | 58693.73 | 0.416 | 0.401–0.481 |
| b64-zeros-65536 | 198777.91 | 170856.60 | 40789.53 | 59525.44 | 0.879 | 0.811–0.976 |
| b64-boundary-12287 | 35857.00 | 32122.77 | 7562.16 | 10904.30 | 0.890 | 0.875–0.970 |
| b64-boundary-12288 | 36355.00 | 31987.12 | 7436.29 | 10683.90 | 0.890 | 0.856–0.908 |
| b64-boundary-12289 | 36539.77 | 32037.77 | 7426.85 | 10862.46 | 0.883 | 0.844–0.985 |
| b64-boundary-65535 | 195835.76 | 173670.13 | 40050.56 | 57505.45 | 0.891 | 0.867–1.004 |
| b64-boundary-65537 | 198308.25 | 175187.51 | 40826.61 | 56435.82 | 0.888 | 0.787–0.967 |
| hex-boundary-8191 | 37690.88 | 15123.16 | 5987.44 | 7680.61 | 0.400 | 0.356–0.428 |
| hex-boundary-8192 | 37386.94 | 15389.23 | 5890.81 | 7665.26 | 0.409 | 0.398–0.477 |
| hex-boundary-8193 | 38100.70 | 16001.85 | 5937.20 | 7684.83 | 0.425 | 0.400–0.439 |
| hex-boundary-16383 | 76594.51 | 31707.38 | 11910.94 | 14995.68 | 0.424 | 0.370–0.452 |
| hex-boundary-16384 | 76155.23 | 31723.98 | 11850.84 | 15073.67 | 0.417 | 0.365–0.434 |
| hex-boundary-16385 | 80964.90 | 31954.98 | 11656.98 | 15269.40 | 0.416 | 0.195–0.482 |

Seven A/A pairs on four representative cases gave paired median B/A ratios 0.940–1.016; individual ratios ranged 0.572–1.531. Raw [A/A samples](results-2026-11-12/aa.json) and [main samples](results-2026-11-12/samples.json) retain the noise. The shortest actual main sample was 18.59ms after calibration. Hardware instruction counts were not measured.

Five alternating process-level peak-RSS pairs use Linux VmHWM only after `/proc/pid/exe` matches the tested binary; this avoids fork-inherited wait4 high-water values. Identical input, output-validation and iteration controls are used. These are process peaks, including startup and input/expected buffers, not isolated allocation counts. [Raw RSS samples](results-2026-11-12/rss.json):

| Case | Baseline peak KiB | Proposed peak KiB |
|---|---:|---:|
| hex-random-13 | 1508 | 1500 |
| b64-random-13 | 1504 | 1500 |
| hex-random-65536 | 2088 | 2112 |
| b64-random-65536 | 2012 | 1952 |
| hex-random-1048576 | 9764 | 9784 |
| b64-random-1048576 | 7756 | 8004 |


## Correctness and alternatives

- All benchmark outputs match Python hex/Base64 outputs, including 0/1/2-byte tails, random/all-zero bytes, 1MiB inputs and the former 12,288-byte Base64 batching boundary and six hex chunk boundaries.
- All 42 tests in seven encoding fixtures pass in both Debug and LLVM Release. New tests cover all 256 hex byte values and Base64 padded/unpadded alphabets through nested views. Existing nonempty nested hex-view and error-precedence tests remain unchanged.
- Each changed conformance golden was recorded twice and its diff reviewed; only new tests and their counts changed. C exact/growing implementations passed 62 ASan/UBSan case checks separately from timing.
- Direct indexing of `Bytes` in hex encode/decode was rejected: ordinary decode regressed about 18%, large valid decode about 13%, and encoding regressed more, despite nearly halving early-invalid decode cost. Decoder production code is unchanged.
- The older growing `BytesBuilder` hex candidate remains rejected. The retained design uses a byte table and reserves only a bounded ASCII batch; empty and single-batch inputs return directly. It improves tiny as well as large controls. A first full-output reservation improved timing but raised exec-specific peak RSS by about 4MiB on a 1MiB input, so it was replaced. Its [rejected-probe evidence](reserved-probe-2026-11-12/README.md) is retained separately.
- The previous UTF-16 candidate remains rejected and is not part of this change. No compiler/ownership work, public API addition or dependency change is included.

## Reproduction

Build one compiler/runtime from the baseline commit above and one from the proposed revision using `cargo xtask runtime` then `cargo build --release --locked -p ms-cli`, in separate checkouts. `BASE_MS` and `NEW_MS` below name those executables; both embed their revision's stdlib. Use the **same probe source** for both. Do not run timing alongside builds or other benchmarks.

```sh
BASE_MS=/path/to/baseline/target/release/ms
NEW_MS=/path/to/proposed/target/release/ms
$BASE_MS build bench/perf/codec-encoding/probe.ms --build-type Release -o /tmp/codec-baseline
$NEW_MS build bench/perf/codec-encoding/probe.ms --build-type Release -o /tmp/codec-proposed
cc -O3 -march=x86-64-v3 -mtune=generic -std=c11 -Wall -Wextra -Werror bench/perf/codec-encoding/driver.c bench/perf/codec-encoding/codec.c -o /tmp/codec-c
python3 bench/perf/codec-encoding/run.py /tmp/codec-baseline /tmp/codec-proposed /tmp/codec-c --output /tmp/codec-results --pairs 11
python3 bench/perf/codec-encoding/aa.py /tmp/codec-results /tmp/codec-baseline /tmp/codec-proposed
python3 bench/perf/codec-encoding/rss.py /tmp/codec-results /tmp/codec-baseline /tmp/codec-proposed
```

The probe and C source retain decode operations for validation-path controls, but the committed timing matrix filters to the changed encoders. Benchmarks require Linux CPU affinity and Python3; no third-party Python libraries are used. Checksum or output mismatches fail the runner. Current results are from one shared VM and are evidence for these implementations, not universal platform guarantees.

## 2026-11-14: Base64 and hex run in Rust natives

Padded and unpadded Base64 and hex encode and decode now call small Rust natives (`crates/ms-std-core/src/encoding`) that write into a pre-sized buffer a group at a time and find bad digits with one OR-reduction instead of a branch per byte. The padded Base64 decoder was pure Manuscript before; it now shares the native with the unpadded one. Error kinds and their precedence (budget, then parity or padding, then digits) are unchanged and covered by the existing fixtures plus a hex unit test.

Measured on 8 MiB of text-like bytes, Release LLVM build, same shared VM, best of 7 per run and three runs each (`/tmp` probe, not committed): before 219/143-164/357-503/205-277 MB/s, after 981-990/807-811/774-792/1152-1262 MB/s for Base64 encode, Base64 decode, hex encode, hex decode. Go 1.24 `encoding/base64` and `encoding/hex` on the same machine and input, best of 7: 489/634/498/486 MB/s. A differential of 700 random valid and invalid inputs against Python's `base64` and `bytes.fromhex` matched exactly.
