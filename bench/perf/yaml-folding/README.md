# Folded YAML plain scalars

## 2026-11-12

Baseline `ff4ce5edff87e46edf1f1f105bc93cd1b6236217`. Folded plain scalars
previously copied a growing result for each physical line. A StringBuilder
accumulates content and folding separators once. The no-newline return and
leading/trailing blank handling stay intact.

Actual Manuscript 0.1.0 LLVM Release binaries, Rust 1.99.1, Linux x86_64,
AMD EPYC 9V74 shared VM. CPU affinity selects one permitted CPU and
`MS_CPU_LEVEL=baseline`. Runtime arguments supply line and iteration counts.
Input construction and expected-result generation precede timing. Timed work is
**parse plus stringify**, with output byte lengths consumed in a checked sink.
This is not an isolated fold or parse-only measurement.

Three warmup pairs and 15 alternating measured pairs:

| Physical lines | Baseline ns/operation | Candidate ns/operation | Paired ratio |
| ---: | ---: | ---: | ---: |
| 1 | 2,229 | 2,322 | 1.024 |
| 10 | 5,262 | 5,302 | 0.991 |
| 100 | 31,296 | 29,732 | 0.942 |
| 1,000 | 311,880 | 266,959 | 0.864 |
| 4,000 | 1,654,785 | 1,088,427 | 0.655 |
| 8,000 | 4,736,541 | 2,267,327 | 0.486 |

The apparent one-line regression did not persist in longer batches of 100,000
operations: 25 measured alternating pairs yielded A/B 1.0034; A/A 0.9921.
Small differences are treated as noise. Large improvements are scoped to this
long folded-scalar shape. Gathering physical lines remains unchanged.

A separate 113-case differential compares complete printed parsed values,
serialized text and errors byte-for-byte between baseline/candidate native
programs. It includes blank runs, leading/trailing blanks, CRLF, Unicode and
malformed boundaries. All 175 YAML fixture tests pass. The existing long-flow
test now pins exact folded strings for ordinary, blank-run and Unicode cases.
Independent review checked source and recomputed ratios.

No equivalent full-contract C YAML parser was available; no C-parity ratio is
claimed. Hardware instruction counts were unavailable. Evidence is Linux-only.

## Reproduction

Build `main.ms` with baseline and candidate compilers using
`ms build main.ms --build-type Release -o SCRATCH/base` (or `SCRATCH/new`).
Build `correctness.ms` similarly as `check-base` and `check-new`, then:

```sh
python3 compare.py SCRATCH
python3 small.py SCRATCH
python3 differential.py SCRATCH
```

Raw samples, exact differential inputs and executable/source hashes are under
`results-2026-11-12`. Retained binaries and sources are in
`/workspace/scratch/yaml-folding-perf`. No builds ran during timed measurements.
