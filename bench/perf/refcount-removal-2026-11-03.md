# Refcount removal, 2026-11-03

Same-machine before/after for the concurrency redesign's workstream B (runtime objects lose their reference count; a copy goes through the object's clone entry and a one-owner value cannot be copied). Three Release `ms` binaries (`cargo xtask runtime`, `cargo build --release --locked -p ms-cli`, LLVM backend) ran the same suites in turn:

- `632c42ba` ("rc"): the last head with reference counts, before the method-value and refcount commits.
- `d34af765` ("pre-B"): the integration head with the streams and promise redesign but with reference counts, so a comparison against it isolates the refcount change from the streams work.
- `d6052382` ("no rc"): the integration head after the refcount removal, with the 13 main commits merged on 2026-11-03.

Machine: Intel Xeon @ 2.10GHz, 4 vCPUs, 15 GB RAM, Linux 6.18 (shared cloud VM), the same class as the [2026-10-28 baseline](baseline-2026-10-28.md). Whole-suite runs on this VM drift by 10 to 15% between runs even for pure integer loops (`int_eq` below moves 0.70 to 0.85 ns across three runs of the same binary), so a case is a regression only when it reproduces alone. Below 1.00x is faster.

## Conclusion

No regression attributable to the refcount removal. Every case flagged by a full run (regex replace and cardinality, `list.partition`, `priority_queue`, `bigint.factorial`, `read_line`, `map_put_get_8k`, `int_eq`, the `c03`, `c25` and `c16` workloads) came back within the run-to-run noise when rerun alone or repeated, with the two binaries alternating. Where the numbers moved beyond noise they moved the other way: `conc_bench` `promise.spawn_wait_all_1000` 0.63x, `set.add_contains` 0.72x, `json.roundtrip` 0.69x, `csv.parse` 0.55x, `yaml.roundtrip` 0.50x, `string.split` 0.63x, `bytes_append` 0.69x (fewer retain/release pairs per element). The web server's resident memory after load rose from 57 MB to 90 MB between `632c42ba` and `d6052382`, but it is the same (93.5 MB vs 89.4 MB) between pre-B and no-rc on the same server source, so it belongs to the streams and promise redesign, not to this change.

## Web (`ms run bench/tools/web_bench.ms -- run 5`)

Pre-B and no-rc serve the same `bench/perf/web/ms` source; both rounds shown. The rc binary cannot build that source (it predates the promise-returning file API), so its row ran the `632c42ba` source from its own checkout and is comparable only loosely.

| measurement | rc `632c42ba` (own source) | pre-B `d34af765` | no rc `d6052382` |
|---|---:|---:|---:|
| `/health` req/s | 203.9k, 201.2k | 157.6k, 155.3k | 168.0k, 174.2k |
| `/user/42` req/s | 181.2k, 167.8k | 155.5k, 158.9k | 165.7k, 159.5k |
| `/top?n=10` req/s | 51.3k, 53.2k | 49.0k, 47.0k | 45.6k, 49.2k |
| `/io` req/s | 1,485, 1,385 | 1,577, 1,455 | 1,570, 1,504 |
| `/health` req/s during `/io` | 93.8k | 82.5k | 76.3k |
| `/io` req/s during `/health` | 1,838 | 1,915 | 1,631 |
| threads, resident memory after load | 7, 56.9 MB | 7, 93.5 MB | 7, 89.4 MB |
| system calls per `/health` request | 2.53 | 2.54 | 2.54 |
| resident memory, 10,000 idle connections | 256 MB | 289 MB | 287 MB |
| `/health` req/s beside 10,000 idle | 188.0k | 164.4k | 159.1k |

Go in the same runs: `/health` 107k to 119k req/s, 15 MB resident; Rust (hyper): 196k to 220k req/s, 4.2 MB.

## Workloads (`ms run bench/tools/workloads.ms -- 5`, min of two rounds, wall ms)

The ten reference solutions were ported from the removed `read_line`/`flush` API to `lines(stdin())` and `flush().wait()` for this run (they had not built since the streams redesign).

| program | rc | pre-B | no rc | no rc / pre-B | Go | Rust |
|---|---:|---:|---:|---:|---:|---:|
| c03-csv-group-sum | 105.7 | 104.9 | 113.3 | 1.08x | 42.9 | 31.0 |
| c05-calculator | 73.0 | 73.6 | 69.4 | 0.94x | 49.7 | 132.5 |
| c09-ciphers | 71.6 | 73.6 | 76.2 | 1.03x | 60.8 | 41.2 |
| c13-inventory-orders | 180.4 | 187.8 | 176.0 | 0.94x | 281.7 | 163.8 |
| c14-dp-suite | 646.0 | 633.2 | 631.3 | 1.00x | 1,661.6 | 472.8 |
| c16-maze-bfs | 34.9 | 36.2 | 38.3 | 1.06x | 35.4 | 38.5 |
| c18-cron-next-runs | 870.4 | 877.1 | 911.3 | 1.04x | 1,190.0 | 782.6 |
| c25-log-analyzer | 24.0 | 20.5 | 22.4 | 1.09x | 51.2 | 21.6 |
| c36-bank-ledger | 109.3 | 115.9 | 119.6 | 1.03x | 118.9 | 63.6 |
| c44-unified-diff | 3.4 | 3.3 | 3.5 | 1.05x | 74.7 | 14.7 |

The Go and Rust columns moved by the same 5 to 15% between the rounds, which is the VM's noise.

## Programs (`ms run bench/tools/programs.ms -- 15`, ns per operation, min of three runs per binary)

`bench_read_line` now reads `lines(stdin())`.

| operation | rc | pre-B | no rc | no rc / pre-B |
|---|---:|---:|---:|---:|
| string_append_50k | 2.95 | 2.32 | 2.36 | 1.02x |
| read_line | 272 | 239 | 263 | 1.10x |
| map_put_get_8k | 29.8 | 27.5 | 29.5 | 1.07x |
| int_eq | 0.76 | 0.70 | 0.79 | 1.13x |
| generic_call | 0.36 | 0.35 | 0.37 | 1.06x |
| try | 0.36 | 0.34 | 0.36 | 1.06x |
| match | 1.57 | 1.58 | 1.61 | 1.02x |
| for_list | 0.60 | 0.59 | 0.57 | 0.97x |

`int_eq` touches no object and still reads 1.13x, which is the noise floor of these runs; `method_call` and `builtin_length` fold to constants.

## Data structures (`ms run bench/tools/datastructures.ms -- 5`, ns per operation)

| operation | rc `632c42ba` | no rc `d6052382` | change |
|---|---:|---:|---:|
| list_append | 3.7 | 3.5 | 0.95x |
| list_get_random | 3.1 | 3.2 | 1.03x |
| list_sort_int | 18.8 | 16.8 | 0.89x |
| list_sort_cmp | 59.7 | 56.6 | 0.95x |
| map_int_put_get | 39.2 | 37.3 | 0.95x |
| map_str_put_get | 44.6 | 42.7 | 0.96x |
| set_int_add_contains | 44.2 | 43.3 | 0.98x |
| string_build_split_join_replace | 27.4 | 30.7 | 1.12x |
| bytes_append | 1.6 | 1.1 | 0.69x |
| pq_int_enqueue_dequeue | 91.9 | 93.2 | 1.01x |
| sorted_map_add_contains | 186.3 | 177.3 | 0.95x |

## Flagged stdlib cases rerun alone (`ms bench <file> --filter <case> --samples 15`, two rounds each, min)

| case | rc | no rc | change |
|---|---:|---:|---:|
| regex.replace_template.literal.2000 | 239,689 | 215,679 | 0.90x |
| regex.replace_template.2000 | 686,390 | 676,704 | 0.99x |
| regex.cardinality.whole.over_limit | 265 | 283 | 1.07x |
| regex.cardinality.whole.1 | 190 | 211 | 1.11x |
| regex.cardinality.first.whole.hit | 154 | 153 | 0.99x |
| list.partition | 1.0 | 1.1 | 1.11x |
| list.concat_reverse | 1.9 | 1.9 | 1.01x |
| list.distinct | 11.5 | 10.9 | 0.95x |
| priority_queue.enqueue_dequeue_400000 | 104.5 | 117.5 | 1.12x |
| bigint.factorial_1000 | 141.6 | 133.6 | 0.94x |

In the full run these had read 1.16x to 1.50x.

## Stdlib (`ms bench bench/perf/stdlib/<file> --samples 7`, median ns per operation)

160 cases; `io_bench.ms` is excluded because it still uses the removed `read_line`/`lines` API, and `fs_bench.ms` because the rc binary predates its API.

| case | 632c42ba (rc) | d6052382 (no rc) | change |
|---|---:|---:|---:|
| archive.tar_pack | 1,206 | 1,086 | 0.90x |
| archive.zip_pack | 520 | 452 | 0.87x |
| archive.zip_unpack | 463 | 508 | 1.10x |
| ascii.invalid.first.1 | 45.6 | 30.2 | 0.66x |
| ascii.invalid.first.1048580 | 48,365 | 37,200 | 0.77x |
| ascii.invalid.first.4096 | 124 | 78.7 | 0.63x |
| ascii.invalid.first.57 | 31.1 | 28.5 | 0.92x |
| ascii.invalid.last.1 | 42.7 | 29.4 | 0.69x |
| ascii.invalid.last.1048580 | 554,282 | 372,672 | 0.67x |
| ascii.invalid.last.4096 | 1,512 | 1,448 | 0.96x |
| ascii.invalid.last.57 | 95.8 | 45.0 | 0.47x |
| ascii.unicode.accent.1 | 41.7 | 29.0 | 0.70x |
| ascii.unicode.accent.2048 | 101 | 73.5 | 0.72x |
| ascii.unicode.accent.524288 | 51,864 | 35,602 | 0.69x |
| ascii.unicode.emoji.1 | 50.9 | 32.0 | 0.63x |
| ascii.unicode.emoji.2048 | 131 | 111 | 0.85x |
| ascii.unicode.emoji.524288 | 158,839 | 142,607 | 0.90x |
| ascii.unicode.first.524288 | 14,257 | 12,953 | 0.91x |
| ascii.unicode.first.8 | 29.5 | 27.3 | 0.93x |
| ascii.unicode.last.524288 | 212,503 | 207,872 | 0.98x |
| ascii.unicode.last.8 | 35.0 | 32.8 | 0.94x |
| ascii.valid.0 | 13.0 | 14.9 | 1.15x |
| ascii.valid.1048579 | 670,366 | 479,330 | 0.72x |
| ascii.valid.4095 | 1,882 | 1,685 | 0.90x |
| ascii.valid.56 | 92.9 | 55.3 | 0.59x |
| ascii.valid.7 | 30.1 | 29.6 | 0.98x |
| bigint.factorial_1000 | 130 | 151 | 1.16x |
| bigint.multiply_100_digits | 122 | 75.1 | 0.62x |
| bitset.add_contains_100000 | 1.6 | 1.5 | 0.98x |
| bitset.add_contains_400000 | 1.5 | 1.5 | 1.04x |
| bytes.append_int32_le | 6.3 | 4.9 | 0.78x |
| bytes.builder | 1.6 | 1.6 | 0.99x |
| bytes.read_int32_le | 10.8 | 9.7 | 0.90x |
| bytes.read_uint32_le | 10.5 | 9.9 | 0.95x |
| compress.gzip | 2.4 | 2.4 | 1.00x |
| compress.roundtrip | 3.6 | 3.4 | 0.96x |
| crypto.sha256 | 0.7 | 0.7 | 1.02x |
| csv.parse | 392 | 217 | 0.55x |
| csv.stringify | 241 | 241 | 1.00x |
| decimal.add_round | 521 | 478 | 0.92x |
| deque.push_pop_both_ends_100000 | 7.4 | 8.1 | 1.10x |
| deque.push_pop_both_ends_400000 | 7.7 | 8.3 | 1.08x |
| encoding.base64_decode | 3.8 | 3.9 | 1.04x |
| encoding.base64_encode | 2.6 | 2.2 | 0.87x |
| encoding.hex_encode | 6.9 | 3.6 | 0.52x |
| html.escape_unescape | 105 | 94.7 | 0.90x |
| html.parse | 2,579 | 1,967 | 0.76x |
| json.navigate | 266 | 260 | 0.98x |
| json.parse | 378 | 407 | 1.07x |
| json.roundtrip | 762 | 522 | 0.69x |
| list.any_early_exit | 0.8 | 0.7 | 0.94x |
| list.append | 0.4 | 0.3 | 0.97x |
| list.at | 0.9 | 1.0 | 1.07x |
| list.callable_key | 0.8 | 0.8 | 1.00x |
| list.callable_key_loop | 0.8 | 0.9 | 1.02x |
| list.chunks | 0.4 | 0.4 | 1.02x |
| list.concat_reverse | 1.8 | 2.2 | 1.19x |
| list.contains | 38,029 | 35,163 | 0.92x |
| list.distinct | 10.9 | 12.6 | 1.16x |
| list.filter | 1.0 | 0.9 | 0.89x |
| list.fold | 0.4 | 0.3 | 0.92x |
| list.for_in | 0.4 | 0.4 | 0.98x |
| list.insert_remove_middle_100000 | 7,804 | 8,709 | 1.12x |
| list.insert_remove_middle_400000 | 34,074 | 35,836 | 1.05x |
| list.map | 0.9 | 0.7 | 0.79x |
| list.max | 0.8 | 0.7 | 0.82x |
| list.max_by | 38,831 | 38,831 | 1.00x |
| list.max_by_loop | 103,116 | 101,066 | 0.98x |
| list.partition | 0.9 | 1.1 | 1.24x |
| list.records_map | 1.2 | 1.2 | 1.05x |
| list.sorted | 16.3 | 13.9 | 0.85x |
| list.sorted_natural | 13.7 | 13.6 | 0.99x |
| list.sum | 0.3 | 0.4 | 1.02x |
| list.windows | 10.0 | 10.9 | 1.09x |
| list.zip | 1.4 | 1.4 | 0.97x |
| map.get_chain | 23.5 | 23.4 | 0.99x |
| map.get_if_let | 23.3 | 23.2 | 0.99x |
| map.get_let | 25.4 | 23.6 | 0.93x |
| map.get_or | 24.9 | 23.4 | 0.94x |
| map.int_put_get | 17.0 | 15.9 | 0.94x |
| map.iterate_entries | 29.6 | 29.0 | 0.98x |
| map.record_key_get | 29.4 | 28.6 | 0.97x |
| map.string_put_get | 18.3 | 19.0 | 1.04x |
| math.sqrt_sin | 11.8 | 6.2 | 0.53x |
| ordering.clamp_if | 1.3 | 1.3 | 0.99x |
| ordering.clamp_method | 1.6 | 1.4 | 0.89x |
| ordering.min_if | 6.7 | 6.5 | 0.97x |
| ordering.min_method | 1.3 | 1.3 | 0.95x |
| path.basename | 63.6 | 43.6 | 0.69x |
| path.join_normalize | 637 | 346 | 0.54x |
| priority_queue.enqueue_dequeue | 84.7 | 75.9 | 0.90x |
| priority_queue.enqueue_dequeue_100000 | 95.7 | 95.5 | 1.00x |
| priority_queue.enqueue_dequeue_400000 | 101 | 120 | 1.19x |
| promise.spawn_then_wait_5000 | 1,092 | 1,124 | 1.03x |
| promise.spawn_wait_all_1000 | 1,764 | 1,115 | 0.63x |
| promise.spawn_wait_each_1000 | 584 | 633 | 1.08x |
| queue.enqueue_dequeue | 4.4 | 4.2 | 0.96x |
| queue.enqueue_dequeue_100000 | 13.2 | 13.5 | 1.02x |
| queue.enqueue_dequeue_400000 | 13.0 | 14.4 | 1.11x |
| random.uuid_v4 | 1,247 | 824 | 0.66x |
| regex.captures_all.0 | 27.2 | 25.9 | 0.95x |
| regex.captures_all.1 | 445 | 500 | 1.12x |
| regex.captures_all.128 | 48,704 | 43,604 | 0.90x |
| regex.captures_all.2000 | 734,509 | 682,681 | 0.93x |
| regex.cardinality.first.grouped.hit | 310 | 342 | 1.10x |
| regex.cardinality.first.whole.hit | 143 | 177 | 1.24x |
| regex.cardinality.first.whole.long | 346,827 | 362,505 | 1.05x |
| regex.cardinality.first.whole.miss | 24.9 | 29.1 | 1.17x |
| regex.cardinality.grouped.1 | 490 | 449 | 0.92x |
| regex.cardinality.grouped.2000 | 700,324 | 802,537 | 1.15x |
| regex.cardinality.named.anonymous.hit | 22.9 | 23.9 | 1.05x |
| regex.cardinality.named.anonymous.long_miss | 21.8 | 22.8 | 1.05x |
| regex.cardinality.named.late.hit | 2,515 | 2,856 | 1.14x |
| regex.cardinality.named.late.miss | 106 | 111 | 1.05x |
| regex.cardinality.named.named.hit | 345 | 367 | 1.06x |
| regex.cardinality.named.whole.hit | 24.7 | 25.8 | 1.04x |
| regex.cardinality.named.whole.long_miss | 23.2 | 23.0 | 0.99x |
| regex.cardinality.whole.0 | 25.2 | 27.9 | 1.11x |
| regex.cardinality.whole.1 | 188 | 222 | 1.18x |
| regex.cardinality.whole.128 | 19,292 | 19,075 | 0.99x |
| regex.cardinality.whole.2000 | 308,389 | 315,076 | 1.02x |
| regex.cardinality.whole.empty_matches | 449 | 431 | 0.96x |
| regex.cardinality.whole.long | 469,126 | 363,363 | 0.77x |
| regex.cardinality.whole.over_limit | 247 | 370 | 1.50x |
| regex.find_all | 115 | 119 | 1.04x |
| regex.matches | 70.3 | 69.1 | 0.98x |
| regex.named_captures.1 | 259 | 253 | 0.98x |
| regex.named_captures.8 | 784 | 865 | 1.10x |
| regex.replace_all | 114 | 109 | 0.96x |
| regex.replace_template.0 | 27.3 | 27.6 | 1.01x |
| regex.replace_template.1 | 446 | 436 | 0.98x |
| regex.replace_template.128 | 57,124 | 49,791 | 0.87x |
| regex.replace_template.2000 | 659,058 | 808,597 | 1.23x |
| regex.replace_template.literal.1 | 144 | 150 | 1.04x |
| regex.replace_template.literal.2000 | 205,187 | 264,271 | 1.29x |
| regex.replace_template.mixed_long_short.2000 | 1,562,000 | 1,530,000 | 0.98x |
| regex.replace_template.unused_large | 59.3 | 62.4 | 1.05x |
| set.add_contains | 39.9 | 28.6 | 0.72x |
| sorted_map.add_contains_100000 | 153 | 167 | 1.09x |
| sorted_map.add_contains_400000 | 228 | 255 | 1.12x |
| sse.feed | 683 | 708 | 1.04x |
| string.append_builder | 1.3 | 1.1 | 0.85x |
| string.chars | 18,021 | 15,338 | 0.85x |
| string.concat | 17.7 | 15.6 | 0.88x |
| string.contains | 283 | 306 | 1.08x |
| string.index_char_at | 221 | 204 | 0.92x |
| string.interpolate | 36.3 | 34.2 | 0.94x |
| string.parse_int | 8.5 | 6.8 | 0.79x |
| string.replace | 20,517 | 17,151 | 0.84x |
| string.split | 29,112 | 18,258 | 0.63x |
| string.trim | 27.1 | 16.0 | 0.59x |
| string.upper | 1,751 | 1,273 | 0.73x |
| time.parse_timestamp | 39.8 | 29.2 | 0.73x |
| time.timestamp_to_string | 192 | 204 | 1.06x |
| toml.parse | 2,131 | 2,402 | 1.13x |
| url.encode_component | 96.6 | 76.9 | 0.80x |
| url.parse | 533 | 530 | 0.99x |
| yaml.parse | 4,445 | 4,056 | 0.91x |
| yaml.roundtrip | 8,768 | 4,422 | 0.50x |
| yaml.stringify | 494 | 503 | 1.02x |

