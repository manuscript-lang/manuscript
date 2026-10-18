Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 1.84 | 2.93 | 0.63x |
| read_line | 200000 | 59.79 | 64.70 | 0.92x |
| map_put_get_8k | 16000 | 33.83 | 31.95 | 1.06x |
| int_eq | 10000000 | 1.04 | 0.98 | 1.05x |
| generic_call | 1000000 | 0.05 | 0.28 | 0.18x |
| method_call | 1000000 | 0.04 | 0.29 | 0.15x |
| try | 1000000 | 0.67 | 0.56 | 1.19x |
| match | 1000000 | 1.78 | 1.53 | 1.16x |
| builtin_length | 1000000 | 0.05 | 0.28 | 0.17x |
| for_list | 1000000 | 0.40 | 0.36 | 1.12x |
