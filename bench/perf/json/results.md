# JSON results

`@std/json` `parse` and `stringify` against Node's `JSON.parse` and `JSON.stringify` on the standard documents (`twitter.json`, `canada.json`, `citm_catalog.json`) and a small RPC message. Both sides warm up, then take the median of at least five runs over one second. Throughput is MB of document per second; the last column is Node time over Manuscript time, so above 1.00x Manuscript is faster. Reproduce with `sh bench/perf/json/run.sh` (needs `node`); compare only runs from one machine.

## main at c1b81215 (2026-10-25)

linux/amd64, four cores, Node v22.22.0, `ms` Release build (LLVM).

| document | operation | Node MB/s | Manuscript MB/s | Manuscript speed |
|---|---|---:|---:|---:|
| small | parse | 190 | 230 | 1.21x |
| small | stringify | 299 | 352 | 1.18x |
| twitter | parse | 569 | 770 | 1.35x |
| twitter | stringify | 364 | 1266 | 3.48x |
| canada | parse | 162 | 419 | 2.58x |
| canada | stringify | 128 | 355 | 2.78x |
| citm_catalog | parse | 671 | 904 | 1.35x |
| citm_catalog | stringify | 908 | 1269 | 1.40x |

Manuscript is ahead of V8 on every row. `parse` builds a `JsonValue` tree, the same work `JSON.parse` does for a JavaScript value; typed `parse[T]` into records is a separate path and is not measured here.

## History

| Change | twitter parse | canada parse | citm parse | PR |
|---|---:|---:|---:|---|
| Before the compact document arena | 0.24-1.0x on every row | | | |
| Compact document arena, SWAR scans, moved results | 0.60x | 2.4x | 0.75x | #1203 |
| Runtime builds the tree while scanning; SSE2 scans | 1.0-1.3x | 2.2x | 0.85-1.0x | #1209 |
| Exactly sized reserved maps | 1.05-1.08x | 2.0-2.5x | 1.13-1.44x | #1210 |
| Bulk object fill, cheaper tree drop | 1.13-1.16x | 2.0-2.3x | 1.2-1.5x | #1212 |
