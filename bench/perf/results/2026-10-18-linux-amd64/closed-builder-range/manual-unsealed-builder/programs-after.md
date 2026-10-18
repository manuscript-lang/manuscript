Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 3.47 | 2.83 | 1.23x |
| read_line | 200000 | 58.71 | 65.17 | 0.90x |
| map_put_get_8k | 16000 | 33.00 | 32.26 | 1.02x |
| int_eq | 10000000 | 1.02 | 0.95 | 1.07x |
| generic_call | 1000000 | 0.05 | 0.28 | 0.18x |
| method_call | 1000000 | 0.04 | 0.28 | 0.16x |
| try | 1000000 | 0.58 | 0.56 | 1.02x |
| match | 1000000 | 3.47 | 1.51 | 2.29x |
| builtin_length | 1000000 | 0.05 | 0.27 | 0.17x |
| for_list | 1000000 | 0.45 | 0.40 | 1.13x |
