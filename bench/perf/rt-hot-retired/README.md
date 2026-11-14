# Retiring `ms-rt-hot`: speed against `main`

Dated 2026-11-14. Machine: shared cloud VM (wall times vary by up to 10%; instruction counts from `valgrind --tool=callgrind` are the reliable column). Baseline: `main` before the stack (#3844, #3852, #3853) and this change; candidate: this branch. Both built with `ms build` (release, LLVM).

Rerun: `ms build bench/perf/rt-hot-retired/hot.ms -o /tmp/hot && /tmp/hot` (prints microseconds), and `MS=... sh bench/perf/engineering/run.sh`.

## Loops (`hot.ms`, microseconds, best of three)

| loop | main | this change |
| --- | --- | --- |
| `Set[Int].contains` | 9,200 | 8,900 |
| `Map[Int, Int].get` | 13,400 | 8,600 |
| `Map[String, Int].get` (inline keys) | 17,000 | 17,100 |
| `StringBuilder.append` x200 | 689,000 | 662,000 |
| `Bytes.int32_le` | 11,000 | 12,200 to 13,700 (a call now) |
| `String.view` | 15,500 | 9,200 |

`Map[String, Int].get` is 27.8M instructions on `main` and 27.2M here for 300k lookups.

## Engineering suite (output byte-identical to `main` for all eight programs)

| task | main (ms) | this change (ms) | instructions |
| --- | --- | --- | --- |
| logstats | 69.6 | 74.0 | +3.3% (path keys are over 15 bytes, so hash and equality are calls) |
| csvgroup | 173.4 | 183.1 | +1% |
| wordfreq | 270.1 | 233.8 | fewer |
| sortrecords | 298.0 | 295.9 | equal |
| grep | 36.1 | 35.1 | equal |
| jsonsum | 160.5 | 160.7 | equal |
| dedupe | 305.1 | 255.6 | fewer |
| report | 174.7 | 173.4 | 1,757M against 1,791M |

Open gaps: lookups with keys of 16 bytes or more call `msrt_string_hash` and `msrt_string_eq` (about 20 instructions each per lookup), and `Bytes.int32_le` calls `msrt_bytes_read_word`. Both were inlined by the hot crate; the Manuscript-side replacement would need a word loop in the generated MIR.

Compile time of `wordfreq`: 0.59 s here against 0.65 s on `main`.
