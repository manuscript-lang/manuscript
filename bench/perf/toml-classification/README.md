# TOML table-array classification

## 2026-11-12

Baseline `b465421aa1759a09692fccd3061d7c731081cd47`. Before this change,
`section_kind` materialized and copied table payloads only to ask whether every
array element was a table. The candidate uses a direct predicate, retaining the
nonempty condition and existing emission. No thresholds or API changes.

Measurements use actual compiled Manuscript 0.1.0 LLVM Release binaries on the
same Linux x86_64 AMD EPYC 9V74 shared VM, built with Rust 1.99.1. The runner pins
to one permitted CPU and sets `MS_CPU_LEVEL=baseline`. Runtime arguments select
shape, size and iterations. Input construction, parsing and expected-output
creation precede timing. Each timed call serializes an owned output; its byte
length contributes to a checked checksum. Every process emits its complete
expected output, which must match byte-for-byte across binaries.

Three warmup pairs precede 25 measured pairs with alternating execution order.
Each measured batch lasts roughly 0.1 seconds. No builds or other benchmarks ran
concurrently. Ratios are medians of paired candidate/baseline times, not ratios
of the separately reported timing medians. Raw samples and ranges are retained.

| Shape | Elements | Baseline ns/call | Candidate ns/call | Paired ratio |
| --- | ---: | ---: | ---: | ---: |
| Ordinary Unicode/scalar document | — | 438 | 438 | 1.006 |
| Tables with nested child | 1 | 2,075 | 1,758 | 0.846 |
| Tables with nested child | 20 | 39,034 | 33,177 | 0.845 |
| Tables with nested child | 1,000 | 2,024,394 | 1,675,340 | 0.829 |
| Table prefix then integer | 1 | 1,157 | 994 | 0.846 |
| Table prefix then integer | 20 | 17,549 | 13,778 | 0.791 |
| Table prefix then integer | 1,000 | 896,426 | 690,925 | 0.779 |
| Scalar array | 0 | 199 | 196 | 1.004 |
| Scalar array | 20 | 1,655 | 1,615 | 0.988 |
| Scalar array | 1,000 | 72,419 | 70,800 | 0.973 |

A/A medians: ordinary 1.0007, 20 tables 1.0012, empty array 0.9991, 20 scalar
items 0.9941. Ordinary/empty controls establish no material regression; do not
interpret their tiny differences as gains. Table and mixed-array gains are
15–22% for these shapes, not whole-program gains.

This is a baseline/candidate comparison. An equivalent optimized C TOML
serializer preserving this API's insertion order, table classification,
Unicode quoting, raw date validation and limits was not available. A custom C
subset would not establish parity, so no C ratio is claimed. Instruction counts
were unavailable; allocation removal is established by source, not an allocator
counter. Measurements are Linux x86_64 only.

The existing test `TOML stringify round trips scalars tables and arrays of tables`
now includes empty, mixed early/late, nested, singleton and empty-table controls,
Unicode, exact output text and byte-limit boundaries. All 18 TOML tests pass
with both baseline and candidate compilers. Independent source and measurement
review approved the candidate.

### Reproduction

Build `main.ms` with the baseline and candidate Release compilers, preserving
binaries as `SCRATCH/base` and `SCRATCH/new` and their build sidecars. For example:

```sh
BASELINE_MS build main.ms --build-type Release -o SCRATCH/base
CANDIDATE_MS build main.ms --build-type Release -o SCRATCH/new
python3 run.py SCRATCH
python3 aa.py SCRATCH
```

The retained binaries and baseline compiler are in
`/workspace/scratch/structured-data-perf`. The measured source differs from the
committed source only by formatter whitespace. [Metadata](results-2026-11-12/metadata.json)
records executable and source identities; [samples](results-2026-11-12/samples.json)
and [A/A controls](results-2026-11-12/aa.json) preserve every measurement.
