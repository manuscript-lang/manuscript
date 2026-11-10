# CSV stream fragmentation, 2026-11-10

`csv_rows` formerly concatenated the whole unfinished record and sliced it back
out on every chunk. Scanning resumed at the previous offset, but these immutable
byte copies made fragmented records quadratic (#3362). The repair retains owned
fragments, scans each incoming chunk once and joins only at completion or EOF.
Whole chunks with complete records decode directly. Fragment metadata costs one
`Bytes` slot per nonempty unfinished chunk: memory stays linear but uses more
metadata for tiny chunks. `max_record_bytes` still counts encoded record bytes.

The latest broad [baseline](../baseline-2026-10-28.md) has no fragmented CSV stream
case. This focused same-machine comparison uses current-main code plus the
independent empty-stream option fix at `cace8b98094541f60916e80efef5f66f81ab592c`.
The exact implementation delta is [fix.patch](results-2026-11-10/fix.patch).

## Measurement

Linux 6.18.57 x86-64, Intel Xeon Platinum 8573C, shared five-vCPU cloud VM;
Rust 1.99.1, Release compiler and Release/Cranelift programs, CPU 0 pinned with
`taskset`. Both programs link the same native archive. No compilation or other
benchmark/test work ran during the five alternating process pairs.

The [producer](probe.ms) builds inputs before timing. Every read checks the full
decoded cell, exactly one row and EOF; malformed controls require `EBADMSG`.
The checksum consumes every payload length. Timings include source chunk copies,
stream construction, result checking and destruction; they exclude input setup,
compilation, process launch and printing. Large cases do four reads per sample;
small and malformed controls do 20,000. Each case has six samples per process;
sample zero is warm-up and excluded. Values below are medians of the remaining
25 samples per side, in microseconds per read.

| Plain payload bytes | 1-byte chunks before | after | 64-byte chunks before | after |
| --- | ---: | ---: | ---: | ---: |
| 4,096 | 637.85 | 322.11 | 12.32 | 6.96 |
| 8,192 | 1,746.90 | 606.04 | 30.39 | 12.93 |
| 16,384 | 5,336.45 | 1,246.09 | 89.40 | 25.79 |
| 32,768 | 32,850.41 | 2,626.23 | 519.43 | 53.77 |
| 65,536 | 185,045.65 | 5,251.06 | 2,875.21 | 111.43 |

The large quoted Unicode/multiline/escaped control improves from 5,373 to 1,355
microseconds with one-byte chunks, and 196 to 125 with 64-byte chunks. Its
whole-record control is 103 to 106 microseconds. Whole-record plain cases range
from unchanged to 6% faster. Small valid, final-tail and malformed controls range
from 10% faster to 5% slower; these small differences are within this shared host's
observed variation. No cross-platform or instruction-count claim is made.

[summary.csv](results-2026-11-10/summary.csv) contains aggregate results for every
case, including all controls. The measurement run produced 2,340 timing rows;
individual timing records are omitted from this tree. Each process exited zero,
and an external check required all 39 case identities, samples 0 through 5
exactly once, positive timers and exact expected checksums. Input sizes and case
identity were checked as well as the producer's native byte comparisons.
[manifest.json](results-2026-11-10/manifest.json) records executable, compiler,
producer and patch SHA-256 hashes, execution order and environment.

## Reproduction

Build a compiler at the baseline commit with `cargo xtask runtime` followed by
`cargo build --release --locked -p ms-cli`; save the compiler as `ms-before`.
Apply the retained patch with `git apply --unidiff-zero` to that tree, rebuild `ms-cli` and save
it as `ms-after`. The native archive is unchanged. Keep this producer identical
for both compilers, and use a writable `XDG_CACHE_HOME` for both.

```sh
MS_BACKEND=cranelift /absolute/ms-before build /absolute/probe.ms --build-type Release -o /tmp/csv-before
MS_BACKEND=cranelift /absolute/ms-after build /absolute/probe.ms --build-type Release -o /tmp/csv-after
taskset -c 0 /tmp/csv-before > /tmp/csv-before-0.csv
taskset -c 0 /tmp/csv-after > /tmp/csv-after-0.csv
```

Repeat five before/after pairs, reversing their process order on odd pairs.
Keep generated raw timing output outside git, as in the `/tmp` paths above.
Check each process status and all 234 output rows. CSV columns are case name,
chunk bytes, input bytes, operations, sample index, elapsed nanoseconds and
checksum. Discard sample zero for each case; divide nanoseconds by operations
and take the median of the remaining values across processes.

Functional regressions in `csv-rows.ms` cover long escaped Unicode/multiline
records, split CRLF/UTF-8, exact/exceeded budgets, interleaved empty chunks and
continued reads after errors. The latter matters because `Through` permits a
caller to keep reading: buffered suffixes and quote state must both advance
before returning a size error. Independent review caught stale prefix bytes in
an initial prototype, and the continued-read regression now preserves baseline
behavior.
