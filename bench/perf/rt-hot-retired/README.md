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
| `Bytes.int32_le` | 11,400 | 6,400 |
| `String.view` | 15,500 | 9,200 |

`Map[String, Int].get` is 27.8M instructions on `main` and 27.2M here for 300k lookups.

## Engineering suite against `main` at ef253e785 (maps held in memory, #3867)

Output is byte-identical to `main` for all eight programs. Instructions from callgrind, millions; wall time is the best of seven runs on the shared VM (ms).

| task | main | this change | change | wall main | wall this change |
| --- | --- | --- | --- | --- | --- |
| logstats | 874.3 | 861.4 | -1.5% | 64.6 | 60.5 |
| csvgroup | 2,485.3 | 2,480.0 | -0.2% | 164.6 | 162.9 |
| wordfreq | 1,964.6 | 1,931.1 | -1.7% | 261.1 | 230.4 |
| sortrecords | 2,010.5 | 2,008.8 | -0.1% | 286.8 | 288.1 |
| grep | 244.2 | 245.4 | +0.5% | 34.6 | 34.8 |
| jsonsum | 1,427.1 | 1,423.0 | -0.3% | 160.8 | 158.2 |
| dedupe | 1,748.2 | 1,745.0 | -0.2% | 269.9 | 212.4 |
| report | 1,761.6 | 1,733.0 | -1.6% | 162.5 | 160.1 |

What is inlined without the hot crate: map and set lookups, `String.view`, `Bytes` fixed-width reads, `String.parse_int`, `String.scalar_at` of an inline ASCII string and a one-byte `contains` (all generated MIR, `rtinline.rs` and `rtstr.rs`); keys of 16 bytes or more hash inline, and keys of 16 to 32 bytes compare with four overlapping word loads. A literal `contains` needle of two or more bytes calls `msrt_string_contains_multi` directly. The runtime hashes an inline key from its words as they are (`hash_str`), which the compiler's probe computes the same way.

The one remaining difference is grep at +0.5% instructions (two more instructions per `contains` call in the caller, which sets up both strings for the call).
