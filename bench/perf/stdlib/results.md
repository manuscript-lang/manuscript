# Standard-library performance results

Part of the [performance benchmark](../README.md). Manuscript only.
2026-10-18 UTC, Go 1.25.1, linux/amd64, AMD EPYC 9V74, 4 vCPU quota.
Baseline main: `2b4962d1`; 30 alternating trials per revision, median ns/op.
All 66 operation names/counts match in each successful execution.

[Raw trials, hashes and paired intervals](../results/2026-10-18-linux-amd64/current-main/).
The [program comparison](../programs/results.md) records Go gaps and tradeoffs.
Rounded small rows do not support precise ratios.

| case | before ns/op | after ns/op | after / before |
|---|---:|---:|---:|
| string.append_builder | 5.5 | 3.0 | 0.55x |
| string.concat | 1,744.0 | 1,789.5 | 1.03x |
| string.split | 21,380.5 | 20,826.0 | 0.97x |
| string.replace_all | 47,481.0 | 48,974.0 | 1.03x |
| string.contains | 4,482.0 | 4,542.0 | 1.01x |
| string.upper | 51,340.5 | 45,289.0 | 0.88x |
| string.trim | 9.0 | 9.0 | 1.00x |
| string.index_char_at | 7.0 | 6.0 | 0.86x |
| string.chars | 112,908.5 | 122,004.0 | 1.08x |
| string.parse_int | 20.0 | 19.0 | 0.95x |
| string.interpolate | 86.0 | 87.0 | 1.01x |
| list.append | 49.0 | 46.0 | 0.94x |
| list.at | 2.0 | 1.0 | 0.50x |
| list.for_in | 0.0 | 0.0 | — |
| list.map | 5.0 | 4.5 | 0.90x |
| list.filter | 10.0 | 8.0 | 0.80x |
| list.fold | 3.0 | 2.0 | 0.67x |
| list.sorted | 109.5 | 110.0 | 1.00x |
| list.contains | 283,197.5 | 180,554.5 | 0.64x |
| list.distinct | 21.0 | 19.0 | 0.90x |
| list.concat_reverse | 18.0 | 18.0 | 1.00x |
| list.records_map | 29.0 | 27.0 | 0.93x |
| map.int_put_get | 112.0 | 122.0 | 1.09x |
| map.string_put_get | 58.0 | 58.5 | 1.01x |
| map.iterate_entries | 246.5 | 230.0 | 0.93x |
| set.add_contains | 82.0 | 85.5 | 1.04x |
| json.parse | 1,263.5 | 1,237.5 | 0.98x |
| json.roundtrip | 2,117.5 | 2,003.5 | 0.95x |
| csv.stringify | 279.0 | 271.0 | 0.97x |
| csv.parse | 209.0 | 199.0 | 0.95x |
| encoding.base64_encode | 1.5 | 1.0 | 0.67x |
| encoding.base64_decode | 1.0 | 1.0 | 1.00x |
| encoding.hex_encode | 2.0 | 2.5 | 1.25x |
| crypto.sha256 | 0.0 | 0.0 | — |
| bytes.builder | 5.5 | 5.0 | 0.91x |
| regex.find_all | 289.5 | 293.0 | 1.01x |
| regex.matches | 94.5 | 92.0 | 0.97x |
| regex.replace_all | 316.0 | 322.5 | 1.02x |
| path.join_normalize | 542.0 | 548.5 | 1.01x |
| path.basename | 16.0 | 12.0 | 0.75x |
| url.parse | 370.5 | 368.5 | 0.99x |
| url.encode_component | 134.5 | 132.0 | 0.98x |
| math.sqrt_sin | 8.0 | 7.0 | 0.88x |
| yaml.parse | 7,702.0 | 7,696.0 | 1.00x |
| yaml.roundtrip | 11,166.0 | 11,009.5 | 0.99x |
| toml.parse | 5,889.0 | 5,582.0 | 0.95x |
| html.parse | 1,731.0 | 1,875.0 | 1.08x |
| html.escape_unescape | 206.0 | 200.5 | 0.97x |
| bigint.factorial_1000 | 267.0 | 234.0 | 0.88x |
| decimal.add_round | 1,475.5 | 1,446.5 | 0.98x |
| compress.gzip | 2.0 | 2.0 | 1.00x |
| compress.roundtrip | 5.5 | 4.0 | 0.73x |
| time.parse_timestamp | 302.0 | 310.0 | 1.03x |
| queue.enqueue_dequeue | 11.0 | 9.5 | 0.86x |
| priority_queue.enqueue_dequeue | 147.0 | 140.0 | 0.95x |
| archive.zip_pack | 1,378.5 | 1,409.0 | 1.02x |
| archive.tar_pack | 5,492.5 | 4,663.0 | 0.85x |
| archive.zip_unpack | 8,999.0 | 8,410.0 | 0.93x |
| sse.feed | 1,666.0 | 1,693.5 | 1.02x |
| time.timestamp_to_string | 100.0 | 95.0 | 0.95x |
| random.uuid_v4 | 431.0 | 438.0 | 1.02x |
| fs.write_file_64k | 21,002.5 | 20,472.0 | 0.97x |
| fs.read_file_64k | 42,939.5 | 44,587.5 | 1.04x |
| fs.stat | 5,669.5 | 6,510.5 | 1.15x |
| fs.list_200 | 70,614.0 | 73,753.5 | 1.04x |
| log.info | 3,778.0 | 3,697.0 | 0.98x |

List search improves about36%; the isolated polling-only control also improves
about49%. The host fs.stat row regresses about15% (paired95% ratio interval
1.030–1.279) and remains unresolved. Other nominal slowdowns have intervals
including1 in this run; that is inconclusive rather than proof of equivalence.

Earlier tables/raw trials under the parent results directories use older main
revisions and are historical. Run `make stdlib-bench BENCHREPEATS=30` to profile
the current revision; compare already-built revisions in alternating order.
