# Standard-library performance results

The [bounded-match/index final control](../results/2026-10-18-linux-amd64/bounded-match-index/library-identical-control/)
retains all 66 rows for 30 trials. Before/after generated Go and normalized native
executables are byte-identical; the diagnostic timing variation is not a changed algorithm.

The [closed-builder/range follow-up](../results/2026-10-18-linux-amd64/closed-builder-range/library-identical-control/)
retains all66 rows for30 trials. Its generated Go and normalized native executable
are byte-identical before/after; diagnostic timing variation is not an algorithm change.

The [counter-aggregation follow-up](../results/2026-10-18-linux-amd64/counter-aggregation/library/)
retains all66 library rows and30 balanced before/after trials.

Latest Result-bound follow-up: the library generated Go and normalized executable
are byte-identical to PR #694; see the [diagnostic control and hashes](../results/2026-10-18-linux-amd64/result-payload-bounds/).
The table below remains the earlier merged runtime/lowering comparison.

2026-10-18 UTC; Go1.25.1, linux/amd64, AMD EPYC9V74, four-vCPU quota.
Baseline d710e9bf (PR#688); thirty alternating executions per revision.
All66 operation counts/checksums match in every process. These medians use raw
elapsed nanoseconds divided by operations, preserving sub-nanosecond precision.
Both revisions compile the same current harness and sources with matching native
flags; compilation/tests do not overlap measurements.

[Raw samples, hashes, intervals and focused controls](../results/2026-10-18-linux-amd64/complete-parity/).
[Program comparison and proof limits](../programs/results.md).

Median of 30 alternating runs; all 66 counts and checksums verified.

| operation | ops | before ns/op | after ns/op | after/before |
|---|---:|---:|---:|---:|
| string.append_builder | 100000 | 3.31255 | 3.63007 | 1.096x |
| string.concat | 20000 | 2041.49 | 1975.28 | 0.968x |
| string.split | 200 | 22715.2 | 22535.8 | 0.992x |
| string.replace_all | 200 | 50676.2 | 51318.7 | 1.013x |
| string.contains | 2000 | 4660.84 | 4593.52 | 0.986x |
| string.upper | 200 | 45596.1 | 49010.6 | 1.075x |
| string.trim | 100000 | 9.84666 | 10.0228 | 1.018x |
| string.index_char_at | 100000 | 6.62304 | 7.26073 | 1.096x |
| string.chars | 20 | 135583 | 128163 | 0.945x |
| string.parse_int | 100000 | 20.4276 | 20.237 | 0.991x |
| string.interpolate | 100000 | 89.4409 | 89.2455 | 0.998x |
| list.append | 200000 | 45.4148 | 43.4384 | 0.956x |
| list.at | 200000 | 2.02209 | 1.84017 | 0.910x |
| list.for_in | 100000 | 0.842095 | 0.851415 | 1.011x |
| list.map | 100000 | 5.3083 | 5.18923 | 0.978x |
| list.filter | 100000 | 9.21579 | 9.51767 | 1.033x |
| list.fold | 100000 | 2.75102 | 3.7566 | 1.366x |
| list.sorted | 100000 | 114.13 | 115.186 | 1.009x |
| list.contains | 100 | 183082 | 183693 | 1.003x |
| list.distinct | 100000 | 20.9682 | 21.6506 | 1.033x |
| list.concat_reverse | 100000 | 20.7653 | 19.9987 | 0.963x |
| list.records_map | 100000 | 29.4906 | 28.9426 | 0.981x |
| map.int_put_get | 200000 | 116.478 | 41.6686 | 0.358x |
| map.string_put_get | 100000 | 63.8765 | 74.7138 | 1.170x |
| map.iterate_entries | 100000 | 216.031 | 231.104 | 1.070x |
| set.add_contains | 200000 | 86.8609 | 84.4924 | 0.973x |
| json.parse | 5000 | 1336.44 | 1326.99 | 0.993x |
| json.roundtrip | 5000 | 2084 | 2254.07 | 1.082x |
| csv.stringify | 5000 | 276.244 | 289.566 | 1.048x |
| csv.parse | 5000 | 238.276 | 184.45 | 0.774x |
| encoding.base64_encode | 157689 | 2.85945 | 1.71083 | 0.598x |
| encoding.base64_decode | 157689 | 2.07385 | 1.61919 | 0.781x |
| encoding.hex_encode | 157689 | 2.12304 | 3.39621 | 1.600x |
| crypto.sha256 | 157689 | 0.584514 | 0.74281 | 1.271x |
| bytes.builder | 100000 | 5.51526 | 5.69477 | 1.033x |
| regex.find_all | 2000 | 319.052 | 302.788 | 0.949x |
| regex.matches | 10000 | 99.8416 | 101.68 | 1.018x |
| regex.replace_all | 2000 | 380.026 | 329.485 | 0.867x |
| path.join_normalize | 50000 | 581.954 | 578.548 | 0.994x |
| path.basename | 100000 | 13.4001 | 16.9033 | 1.261x |
| url.parse | 20000 | 392.806 | 391.598 | 0.997x |
| url.encode_component | 50000 | 135.95 | 135.872 | 0.999x |
| math.sqrt_sin | 1000000 | 8.4762 | 8.59218 | 1.014x |
| yaml.parse | 2000 | 8129.56 | 7994.99 | 0.983x |
| yaml.roundtrip | 2000 | 11542.8 | 11344.7 | 0.983x |
| toml.parse | 2000 | 6098.43 | 6255.65 | 1.026x |
| html.parse | 2000 | 1920.43 | 1910.25 | 0.995x |
| html.escape_unescape | 2000 | 146.7 | 167.29 | 1.140x |
| bigint.factorial_1000 | 1000 | 307.782 | 262.774 | 0.854x |
| decimal.add_round | 20000 | 1537.78 | 1508.09 | 0.981x |
| compress.gzip | 880000 | 2.93046 | 2.79097 | 0.952x |
| compress.roundtrip | 880000 | 6.23036 | 5.31032 | 0.852x |
| time.parse_timestamp | 20000 | 318.955 | 320.64 | 1.005x |
| queue.enqueue_dequeue | 200000 | 10.3928 | 12.3623 | 1.190x |
| priority_queue.enqueue_dequeue | 100000 | 148.003 | 148.934 | 1.006x |
| archive.zip_pack | 2000 | 1517.47 | 1523.21 | 1.004x |
| archive.tar_pack | 2000 | 4256.04 | 5444.89 | 1.279x |
| archive.zip_unpack | 2000 | 9788.32 | 9811.82 | 1.002x |
| sse.feed | 2000 | 1864.89 | 1841.29 | 0.987x |
| time.timestamp_to_string | 20000 | 109.023 | 102.411 | 0.939x |
| random.uuid_v4 | 20000 | 459.625 | 443.403 | 0.965x |
| fs.write_file_64k | 200 | 21622.7 | 21036.8 | 0.973x |
| fs.read_file_64k | 200 | 49420.2 | 46605.6 | 0.943x |
| fs.stat | 200 | 6568.46 | 4990.47 | 0.760x |
| fs.list_200 | 1 | 79141.5 | 73042.5 | 0.923x |
| log.info | 20000 | 3979.41 | 3912 | 0.983x |


FS.stat improves about24%; closed Int map put/get about64%. Other rows include
nominal regressions. Changing an earlier allocation-heavy case can move later
collection pauses, so15-process/20-repeat focused controls accompany the complete
sequence. They do not reproduce the large fold/hex/hash/string/map/path/archive
regressions; their after/before ratios are in focused-summary.json. Retain both
views when interpreting the full-suite table. No timing threshold is a CI gate.

The earlier all-library tables used integer-rounded ns/op and, initially, discarded
returned checksums. They remain archived as historical experiments. New runs
validate emitted checksums and raw elapsed metadata before generating a table.
