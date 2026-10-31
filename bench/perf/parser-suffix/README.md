# Parser type-suffix construction — 2026-10-31

These measure the Rust implementation of Manuscript's compiler, **not** generated
Manuscript programs against Rust programs. Both binaries use the same Rust
toolchain, parser, inputs and release settings. They differ only in whether each
`?`/`!` wrapper deep-clones the accumulated type or moves it into the new wrapper.
No checker, lowering, backend or runtime code is exercised.

Baseline: `d4a94aa9283348133542078e22ccaa3b2c9dc348`. The candidate parser SHA-256
and both binary fingerprints are in `results-2026-10-31-initial.json`.
Linux x86_64, kernel 6.18.57, glibc 2.41, AMD EPYC 9V45 VM, pinned CPU 0;
Rust 1.99.1, opt-level 3, debug 1, panic abort, frame pointers enabled.

| Workload | Baseline µs/pass | Candidate µs/pass | Speedup |
| --- | ---: | ---: | ---: |
| One plain signature | 0.536 | 0.541 | 0.99x |
| 256 plain signatures | 106.506 | 106.394 | 1.00x |
| 256 single optional signatures | 121.396 | 118.772 | 1.02x |
| 256 single Result signatures | 128.396 | 124.674 | 1.03x |
| 256 generic optional signatures | 220.648 | 202.094 | 1.09x |
| 16 signatures, 64 optional suffixes each | 964.589 | 62.249 | 15.50x |
| 16 signatures, 128 optional suffixes each | 3924.192 | 117.209 | 33.48x |
| 16 signatures, 256 optional suffixes each | 15926.629 | 226.413 | 70.34x |
| 16 signatures, 512 optional suffixes each | 64737.218 | 448.795 | 144.25x |
| 16 signatures, 256 Result suffixes each | 21647.775 | 308.451 | 70.18x |
| 16 mixed 128-suffix signatures, CRLF | 4664.223 | 154.511 | 30.19x |
| Standard-library source corpus | 4814.255 | 4869.503 | 0.99x |

Ten fresh processes per binary/case, balanced AB/BA order, case order shuffled
with seed 1729. Each process reads inputs, validates successful parsing and warms
three passes before measuring at least 100 ms in batches of 16 passes. Timing
includes parsing, source retention and destruction. Every result is black-boxed
and its node count consumed and checked. Before timing, exact debug trees and
syntax dumps must match, including node IDs, positions and original source.
Errors abort rather than producing artificially fast samples. Source generation,
I/O, validation and process startup are outside the timer.

The raw samples retain distributions and checksums. The runner prints medians
and the paired speedup's central order statistics (second through ninth of ten),
not confidence intervals. Tiny and corpus controls were approximately flat;
their observed variation does not establish a speedup. No universal compiler or
language parity claim follows from the adversarial cases.

For an N-suffix chain on a primitive base such as `Int`, moving removes
N(N−1)/2 deep-cloned nonempty argument
vectors: this count follows from the code, **not** allocator instrumentation.
Heap allocation counters and peak-memory measurements were unavailable. Other
costs, including recursive destruction, symbol interning, lexing and source
retention remain in the measurement.

## Reproduce

Use Rust 1.99.1 and the repository's frame-pointer configuration. Build the
baseline and candidate separately, saving each benchmark executable before
changing checkout. The harness has no additional dependencies:

```sh
cargo build --release --locked -p ms-syntax
rustc --edition=2024 -O -C debuginfo=1 -C panic=abort \
  -C force-frame-pointers=yes \
  --extern ms_syntax=target/release/libms_syntax.rlib \
  -L dependency=target/release/deps \
  bench/perf/parser-suffix/bench.rs -o /tmp/parser-candidate
python3 bench/perf/parser-suffix/run.py \
  /tmp/parser-baseline /tmp/parser-candidate /tmp/parser-results \
  --baseline-revision d4a94aa9283348133542078e22ccaa3b2c9dc348
```

The baseline predates the harness: copy `bench.rs` outside both checkouts first,
then compile the same saved harness against each checkout's release library.
The output directory must be new; historical evidence is never overwritten.
The runner pins itself and its children to the first available CPU on Linux.
Run without concurrent builds or benchmarks. The JSON records platform, affinity,
toolchain, revisions and input/binary/source hashes; a shared VM is not an
isolated machine. These results describe the initial isolated candidate; repeat
the full controls on combined main after merging.
