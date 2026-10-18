Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 3.70 | 2.83 | 1.31x |
| read_line | 200000 | 59.96 | 65.17 | 0.92x |
| map_put_get_8k | 16000 | 34.56 | 32.26 | 1.07x |
| int_eq | 10000000 | 1.03 | 0.95 | 1.08x |
| generic_call | 1000000 | 0.05 | 0.28 | 0.18x |
| method_call | 1000000 | 0.04 | 0.28 | 0.16x |
| try | 1000000 | 0.58 | 0.56 | 1.02x |
| match | 1000000 | 3.57 | 1.51 | 2.36x |
| builtin_length | 1000000 | 0.05 | 0.27 | 0.17x |
| for_list | 1000000 | 0.46 | 0.40 | 1.17x |
