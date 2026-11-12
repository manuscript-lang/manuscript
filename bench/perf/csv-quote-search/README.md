# CSV quote detection

`stringify` formerly materialized every field as a `List[Int]` to decide whether to quote it. The proposed implementation searches for the validated ASCII delimiter, quote, CR and LF, then inspects only the first scalar for the existing Unicode whitespace rule. It preserves the exact backslash-dot special case and all output/error contracts.

## Reproduce

Build the same repository revision before and after the CSV-only patch using the documented runtime and release compiler commands. With those two compiler binaries, build this identical probe twice:

```sh
XDG_CACHE_HOME=/path/to/existing/cache "$BASELINE_MS" build bench/perf/csv-quote-search/probe.ms --build-type Release -o /tmp/csv-baseline
XDG_CACHE_HOME=/path/to/existing/cache "$CANDIDATE_MS" build bench/perf/csv-quote-search/probe.ms --build-type Release -o /tmp/csv-candidate
python3 bench/perf/csv-quote-search/run.py --baseline /tmp/csv-baseline --candidate /tmp/csv-candidate --out /tmp/csv-results --cpu 4
```

Each invocation loads a runtime input file, expected output, options and rows outside the timer. The timed loop calls the actual public `@std/data/csv.ms` `stringify` API, verifies the complete output or exact error kind/message, and accumulates the byte-length checksum. Thus timings include output verification, result handling and deallocation; they do not isolate the private quote helper. Rows contain the input field followed by `tail`. Every process warms up for one tenth of its measured iterations. Counts are equal between variants and calibrated to at least 100 ms on the faster side (cap ten million). Seven paired runs alternate variant order, pinned to CPU 4. Ratios are medians of paired candidate/baseline ratios, not ratios of separately selected best samples.

The independent Python oracle covers 524 cases, including every ASCII scalar at several positions, selected Unicode whitespace and non-whitespace, exact backslash-dot and near-matches, alternate delimiters, CRLF normalization, and errors. Tests in `tests/conformance/fixtures/e2e/stdlib/csv.ms` separately cover zero/multiple rows, single empty fields, multiple columns, exact budgets, invalid line endings and full error values. Five A/A workloads measure timing variability. Do not interpret a small change within A/A variation as a guaranteed gain.

## Native evidence, 2026-11-12

Baseline: `ff4ce5edff87e46edf1f1f105bc93cd1b6236217`. Both applications use compiler/runtime rebuilt from this revision; the candidate differs only in the CSV implementation. Metadata and raw paired samples are in `results-2026-11-12/`. This evidence is from one Linux amd64 machine, not a cross-platform speed guarantee.

The limited allocating C comparison covers ASCII inputs only. It uses different allocation capacities and native byte searches plus unquoted memcpy; it is contextual evidence, not a language-wide comparison or a performance ceiling. See `c-control/README.md` for exact supported invocations and reproduction.

| Workload | Baseline ns/call | Candidate ns/call | Paired ratio |
| --- | ---: | ---: | ---: |
| empty | 138.50 | 126.17 | 0.9048 |
| one | 147.52 | 138.03 | 0.9386 |
| ordinary | 175.60 | 173.54 | 0.9872 |
| comma | 213.33 | 212.74 | 0.9778 |
| quote | 234.36 | 205.31 | 0.8767 |
| newline | 217.91 | 193.09 | 0.8931 |
| space | 196.85 | 198.02 | 1.0046 |
| unicode | 193.61 | 178.56 | 0.9285 |
| unicode-space | 254.56 | 235.82 | 0.9331 |
| dot | 191.02 | 185.19 | 0.9741 |
| ascii-1024 | 1001.75 | 359.46 | 0.3590 |
| unicode-1024 | 7529.88 | 570.08 | 0.0765 |
| early-comma-1024 | 649.00 | 462.36 | 0.7149 |
| late-comma-1024 | 1250.69 | 456.87 | 0.3679 |
| ascii-65536 | 57109.57 | 12704.94 | 0.2249 |
| unicode-65536 | 481405.55 | 32379.41 | 0.0666 |
| early-comma-65536 | 29339.34 | 14182.24 | 0.4836 |
| late-comma-65536 | 67458.90 | 14827.27 | 0.2203 |
| semicolon | 216.44 | 206.72 | 0.9538 |
| crlf | 302.19 | 279.78 | 0.9255 |
| limit | 148.23 | 133.56 | 0.8995 |
| negative | 18.65 | 18.67 | 0.9962 |
| invalid-delimiter | 38.44 | 35.43 | 0.9339 |

Long ASCII fields improve 64–78%, and long Unicode fields improve 92–93% in this workload. Short ordinary fields are effectively unchanged; do not claim a robust small-input gain. Leading-space control is +0.46%, within the A/A variability. The unchanged negative-budget preflight is effectively equal. These results justify removing full-field scalar materialization without a meaningful observed ordinary-input regression.

A/A paired B/A medians: ascii-65536 1.0082, comma 0.9907, empty 0.9995, negative 0.9869, ordinary 0.9898. Raw ranges are retained. No peak-memory or instruction-count claim is made.

The optimized allocating ASCII C control uses `memchr` searches and `memcpy` for unquoted fields. Median ns/call:

| ASCII case | Baseline MS | Proposed MS | C |
| --- | ---: | ---: | ---: |
| empty | 140.71 | 126.33 | 34.18 |
| one | 151.25 | 141.28 | 44.72 |
| ordinary | 179.58 | 179.02 | 45.23 |
| comma | 218.43 | 206.35 | 46.85 |
| ascii1024 | 1036.41 | 358.87 | 99.41 |
| ascii65536 | 56673.81 | 13060.25 | 6059.46 |

These separately paired contextual runs confirm the ordinary field is neutral and the large-field gain persists. C remains faster on these six supported inputs; different allocation/layout/call structures prevent interpreting the remaining gap as compiler overhead. C release and ASan/UBSan each pass 520 independent ASCII fixtures alongside both MS apps.
