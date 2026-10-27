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

Manuscript is ahead of V8 on every row here, and three further runs on the same machine the same day agreed within a few percent (twitter parse 1.29-1.32x, citm stringify 1.41-1.49x). A run on another machine by the JsonValue thread the same day measured twitter parse at 0.94x and citm stringify at 0.88x, so across hardware the range is about 0.9-3.4x; rerun on your own machine before citing a row. `parse` builds a `JsonValue` tree, the same work `JSON.parse` does for a JavaScript value; typed `parse[T]` into records is a separate path and is not measured here.

## History

| Change | twitter parse | canada parse | citm parse | PR |
|---|---:|---:|---:|---|
| Before the compact document arena | 0.24-1.0x on every row | | | |
| Compact document arena, SWAR scans, moved results | 0.60x | 2.4x | 0.75x | #1203 |
| Runtime builds the tree while scanning; SSE2 scans | 1.0-1.3x | 2.2x | 0.85-1.0x | #1209 |
| Exactly sized reserved maps | 1.05-1.08x | 2.0-2.5x | 1.13-1.44x | #1210 |
| Bulk object fill, cheaper tree drop | 1.13-1.16x | 2.0-2.3x | 1.2-1.5x | #1212 |

## 2026-10-27: against serde_json, and the writer

linux/amd64, four shared cores (a slower machine than the table above; compare only within this section), Node v22.22.0. serde_json 1.x `Value` (`from_slice`, `to_vec`, release) measured in the same process protocol: warm-up, then the median of at least five runs over one second.

| document | operation | serde_json MB/s | Manuscript before | Manuscript after |
|---|---|---:|---:|---:|
| twitter | parse | 137 | 465 | 451 |
| twitter | stringify | 827 | 584 | 687 |
| canada | stringify | 425 | 267 | 321 |
| citm_catalog | stringify | 914 | 544 | 689 |

Parse into a tree is about 3x serde_json's `Value`. Stringify was 1.4-1.7x behind; `number_text_valid` built a `Scanner` (and a `Doc`) for every number it wrote, and `Writer::quoted` paid a boundary check and a second scan per string. Validating numbers on the bytes and taking a single-copy path for strings with nothing to escape gives +18% to +27%. What remains is `Writer` call overhead per node (about 30 instructions per node in the generated walker plus the runtime call) and buffer growth.

## 2026-10-27: serde_json harness, writer without revalidation (9f41921f + this change)

linux/amd64, four shared cores, Node v22.22.0, serde_json 1.x `Value` (`bench/perf/json/rust`: `from_slice`, `to_vec`, release). `sh bench/perf/json/run.sh`; MB/s is document size over time, so compare columns within a row. Callgrind counts are `ms ... quick <doc>:stringify` totals (one parse, one tree copy and six stringify runs).

| document | operation | serde_json MB/s | Manuscript before | Manuscript after | after / serde_json |
|---|---|---:|---:|---:|---:|
| small | stringify | 593 | 384 | 393 | 0.66x |
| twitter | stringify | 1420 | 693 | 933 | 0.66x |
| citm_catalog | stringify | 2461 | 1508 | 1514 | 0.62x |
| canada | stringify | 681 | 598 | 608 | 0.89x |
| twitter | parse | 190 | 669 | 707 | 3.7x |
| citm_catalog | parse | 365 | 873 | 850 | 2.3x |

`Writer::finish` validated the whole output as UTF-8 again (12% of twitter stringify instructions) though only whole `&str`s and ASCII are appended; it now hands the buffer over unchecked. Strings under 24 bytes took a byte-at-a-time table walk; the vector scan with its word tail is cheaper at every length measured (twitter 70.96M → 57.59M instructions, citm 132.6M → 126.3M).

Typed stringify of a tree is still 0.62-0.89x serde_json on this machine, so the gap in #1680 is narrowed, not closed: what remains is spread over the generated walker (`json_encode`, ~15% on citm), key and separator bookkeeping and per-value runtime calls.

## 2026-10-27: short names, strings and numbers in one write

linux/amd64, four shared cores, Node v22.22.0, serde_json 1.x. Three runs of `sh bench/perf/json/run.sh`; ranges are the three MB/s values per row. `records` is new: 10,000 typed rows (`id`, `name`, `tags`, `score`, `ok`) written without a `JsonValue`, against serde_json's derived `Serialize` over `Vec<Row>` and Node's `JSON.stringify` of the same objects.

| document | serde_json MB/s | Manuscript before | Manuscript after | after / serde_json |
|---|---:|---:|---:|---:|
| small | 565-624 | 384-393 | 519-549 | 0.86-0.92x |
| twitter | 1453-1585 | 683-693 | 1037-1153 | 0.70-0.79x |
| canada | 651-678 | 598-608 | 640-671 | 0.96-1.03x |
| citm_catalog | 2483-2545 | 1508-1514 | 1736-1781 | 0.69-0.70x |
| records | 738-793 | not measured | 626-666 | 0.80-0.87x |

"Before" is the table above (main at 9f41921f, same machine class, so compare within a row only). Callgrind instructions for the stringify walker on citm (`ms build` then `valgrind --tool=callgrind --toggle-collect='*json_encode*' jb quick citm_catalog:stringify`, one warm-up and five runs): 77.4M → 61.1M.

What changed, all in `Writer` and `ms_rt::scan`:

- A name or string of at most 16 bytes with nothing to escape is checked with two overlapping word tests and written, quotes and colon included, after one capacity check (`push_member_name`, `push_member_quoted`, `push_string_short`). Names were about 190 instructions each in the walker; most of that was bookkeeping around three capacity checks and a byte loop.
- Number text of 1-16 digits with no sign, point or leading zero skips the number grammar (`json_plain_digits`); every other number still goes through `scan_number`.
- The short checks load through raw pointers inside `ms-rt`, which allows `unsafe`; `ms-std-json` still has none.

Remaining profile on `records`: float formatting (~16%, about 300 instructions per float against serde's ~150), the call chain from generated code into `Writer` (wrapper plus method per node), and buffer growth copies. Typed `records` and tree stringify are still below serde_json except on canada, so #1680 stays open.

## 2026-10-27: floats with a short fraction

linux/amd64, four shared cores, Node v22.22.0, serde_json 1.x; three runs of `sh bench/perf/json/run.sh` on main with this change (it includes other changes merged since the section above, so only the last column is the comparison to read).

| document | serde_json MB/s | Manuscript MB/s | Manuscript / serde_json |
|---|---:|---:|---:|
| small | 569-601 | 548-577 | 0.91-1.01x |
| twitter | 1425-1495 | 1575-1640 | 1.05-1.15x |
| canada | 622-656 | 688-767 | 1.09-1.23x |
| citm_catalog | 2454-2639 | 1783-1832 | 0.68-0.73x |
| records | 770-811 | 720-756 | 0.93-0.94x |

A float that is a decimal of one to four fraction digits (`1234.5`, `0.25`, `99.99`) is scaled to an integer, checked by dividing back, and written two digits at a time with the point placed by position; the check yields the same digits as the shortest-round-trip formatter because the quotient of an exact integer by an exact power of ten is the correctly rounded double. `Writer::float` on `i + 0.5` went from about 218 to 135 instructions. The test `plain_decimals_print_as_rust_displays_them` compares 800,000 values in 1e-3..1e11 against Rust's `{}` byte for byte.

citm_catalog is the remaining gap: its time is in the generated `JsonValue` walker and the per-node calls into `Writer`, not in escaping or numbers.

## 2026-10-27: native tree walker and decimal validation

linux/amd64, four shared cores (noisy: two back-to-back runs differed by up to 25% on canada), Node v22.22.0, serde_json 1.x; `sh bench/perf/json/run.sh` on this branch.

| document | serde_json MB/s | Manuscript MB/s | Manuscript / serde_json |
|---|---:|---:|---:|
| small | 586 | 551 | 0.94x |
| twitter | 1400-1500 | 1627-1659 | 1.11-1.16x |
| canada | 654-657 | 471-640 | 0.72-0.98x |
| citm_catalog | 2219-2451 | 2178-2313 | 0.89-1.04x |
| records | 786 | 750 | 0.95x |

Tree stringify (`JsonValue`) no longer calls `Writer` once per node from generated code. The compiler emits one view thunk per type (`value -> kind, payload`), and `msrt_json_w_tree` walks the tree natively through `ms_rt::tree::walk` into the same `Writer`. citm walker instructions: 61.1M → 52.8M. Number text of up to 32 simple decimal bytes (`-?digits(.digits)?`, no leading zero) is validated with word tests (`json_simple_number`) instead of `scan_number`; canada callgrind total is 378M instructions.

canada and citm remain within noise of serde_json rather than clearly above it, so #1680 stays open.

## 2026-10-27: 17-32 byte numbers and fractions

linux/amd64, four shared cores (noisy: wall ratios swing ±15% between runs, so medians of repeated `sh bench/perf/json/run.sh` runs), Node v22.22.0, serde_json 1.x.

| document | serde_json MB/s | Manuscript / serde_json (median of rounds) | range |
|---|---:|---:|---|
| small | 580 | 0.96x | 0.93-1.02x |
| twitter | 1450 | 1.14x | 1.11-1.25x |
| canada | 650 | 1.27x | 1.11-1.73x |
| citm_catalog | 2400 | 0.91x | 0.64-1.36x |
| records | 780 | 0.92x | 0.89-1.26x |

canada's numbers are 17-19 bytes (`-65.613616999999977`), which missed both the 16-byte copy and the byte tail of the decimal check. `push_short` now copies up to 32 bytes with two overlapping 16-byte moves, and the fraction check tests whole words plus one word overlapping the end (`all_digits`). canada tree stringify went from about 0.98x to about 1.27x; `Writer::number` callgrind instructions fell 105M → 76M.

serde_json's own callgrind cost for one `to_vec` of the tree (`valgrind --toggle-collect='*enc*'`, six calls): citm 53.7M, canada 96.8M, twitter 24.5M. Manuscript's citm walker is about 8% more instructions per stringify than serde_json's, matching the 0.91x wall ratio; the cost is spread over the walker (~50 instructions a node), `Writer::key` (~95 a key) and `close`. Inlining `Writer` methods into the walker did not reduce it.
