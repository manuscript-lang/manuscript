# Retiring `ms-rt-hot`: speed against `main`

Dated 2026-11-14. Machine: shared cloud VM (wall times vary by up to 10%; instruction counts from `valgrind --tool=callgrind` are the reliable column). Baseline: `main` before the stack (#3844, #3852, #3853) and this change; candidate: this branch. Both built with `ms build` (release, LLVM).

Rerun: `ms build bench/perf/rt-hot-retired/hot.ms -o /tmp/hot && /tmp/hot` (prints microseconds), and `MS=... sh bench/perf/suite/run.sh`.

## Loops (`hot.ms`, microseconds, best of three)

| loop | main | this change |
| --- | --- | --- |
| `Set[Int].contains` | 9,200 | 8,900 |
| `Map[Int, Int].get` | 13,400 | 8,600 |
| `Map[String, Int].get` (inline keys) | 17,000 | 17,100 |
| `StringBuilder.append` x200 | 689,000 | 662,000 |
| `Bytes.int32_le` | 11,400 | 6,400 |
| `String.view` | 15,500 | 9,200 |

`Map[String, Int].get` is 27.8M instructions on `main` and 27.2M here for 300k lookups.

## Engineering suite against `main` at ef253e785 (maps held in memory, #3867)

Output is byte-identical to `main` for all eight programs. Instructions from callgrind, millions.

| task | main | this change | change |
| --- | --- | --- | --- |
| logstats | 874.3 | 882.2 | +0.9% |
| csvgroup | 2,485.3 | 2,545.5 | +2.4% |
| wordfreq | 1,964.6 | 1,931.2 | -1.7% |
| sortrecords | 2,010.5 | 2,036.5 | +1.3% |
| grep | 244.2 | 246.2 | +0.8% |
| jsonsum | 1,427.1 | 1,423.1 | -0.3% |
| dedupe | 1,748.2 | 1,777.4 | +1.7% |
| report | 1,761.6 | 1,752.6 | -0.5% |

Keys of 16 bytes or more hash inline, keys of 16 to 32 bytes compare with four overlapping word loads, `Bytes` fixed-width readers inline, and a literal needle of two or more bytes calls the general `contains` directly.

Open gap, 0.8 to 2.4%, from callgrind's per-function diff against `main`: `String.parse_int` (sortrecords, csvgroup, logstats), `String.scalar_at` (logstats), `String.contains` (csvgroup) and `msrt_map_entry_ptrs` (dedupe, one step of a map `for` loop) were inlined into the caller by the hot crate and are calls now. Each call costs about the work it replaced, plus call setup; the callers lost 40 to 75M instructions and the calls cost 80 to 120M. The follow-up generates these as MIR.
