# Timestamp format output buffer

## 2026-11-12

`Timestamp.format` built a byte buffer, validated it with a lossy UTF-8 conversion,
then copied valid output into another Rust string. The native wrapper now consumes
the valid buffer. Invalid UTF-8 retains the previous lossy fallback. Token matching,
calendar calculations, zone resolution, error precedence and the byte-oriented
internal formatter are unchanged. No unsafe code or public API changes.

Baseline: `4394064393f99970880086caebd1945c7fdfc314`. The exact production diff,
binary hashes and machine metadata are in [metadata](results-2026-11-12/metadata.json).
Both versions rebuild the GNU and musl runtime archives and embed them in the
Release CLI. Generated programs use the default LLVM and explicit Cranelift
backends on Linux x86_64, Rust 1.99.1. The latest whole-suite
[dated baseline](../baseline-2026-10-28.md) has timestamp parse/string controls,
but no pattern-format case; its different-machine numbers are not used here.

`main.ms` parses the timestamp and resolves an expected output before timing,
then measures repeated public `Timestamp.format` calls. Output lengths feed a
checked checksum. Arguments select the pattern and zone. Ordinary cases run
300,000 calls per process; the 128-repeat long pattern runs 5,000 calls. Each
case has 29 alternating baseline/candidate pairs, with the first four discarded.
Processes share one available CPU affinity; this does not isolate a shared host.
All 696 paired checksums agree. No other builds or benchmarks ran during timing.

The table reports medians of paired candidate/baseline times; lower is faster.
It measures formatting, not whole-application speed. Full samples are retained in
[samples.json](results-2026-11-12/samples.json).

| Pattern | LLVM UTC | LLVM New York | Cranelift UTC | Cranelift New York |
| --- | ---: | ---: | ---: | ---: |
| Empty | 1.009 | 1.020 | 0.992 | 0.995 |
| `hello` | 0.874 | 0.943 | 0.892 | 0.909 |
| `YYYY-MM-DD` | 0.944 | 0.940 | 0.920 | 0.932 |
| Date, time, offset, zone | 0.971 | 0.960 | 0.923 | 0.945 |
| Unicode literals and date | 0.964 | 0.992 | 0.944 | 0.971 |
| Long repeated tokens and Unicode | 0.999 | 0.982 | 0.892 | 0.909 |

Ordinary nonempty formats improve roughly 3–13%; Unicode New York and long LLVM
output show little reliable change. Empty output is separately checked with
longer A/B and identical-binary A/A pairs; see the confirmation evidence.

To reproduce, build `main.ms` with baseline and candidate Release CLIs into a
scratch directory as `base-llvm`, `new-llvm`, `base-clif`, `new-clif`, setting
`MS_BACKEND=cranelift` for the latter two. Run `python run.py SCRATCH_DIRECTORY`.
The script writes raw samples there. Do not run builds concurrently with timers.

Longer empty-pattern confirmation (2,000,000 calls per process, 25 measured pairs)
found LLVM UTC A/B **0.976**, A/A **1.009**; New York A/B **1.011**, A/A **1.012**.
The initial small New York shift did not exceed identical-binary noise; no empty
speedup or regression is claimed. [Raw confirmation](results-2026-11-12/confirm.json)
is reproducible with `python confirm.py SCRATCH_DIRECTORY`.

Separate untimed binaries printed the exact result for all twelve measured
pattern/zone combinations; baseline/candidate outputs matched byte for byte
([outputs](results-2026-11-12/text.json)). The public conformance test additionally
pins Unicode, empty patterns, leap-day/New York output, years 0/10000 from offset
edges, and invalid-zone errors on empty patterns. Internal format tests retain
their raw invalid-UTF-8 coverage. Hardware instruction counters were unavailable
(`perf` is not installed); no instruction-count claim is made.
