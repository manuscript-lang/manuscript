Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 4.01 | 3.63 | 1.11x |
| read_line | 200000 | 62.29 | 67.67 | 0.92x |
| map_put_get_8k | 16000 | 34.34 | 33.62 | 1.02x |
| int_eq | 10000000 | 1.02 | 1.01 | 1.01x |
| generic_call | 1000000 | 0.05 | 0.30 | 0.17x |
| method_call | 1000000 | 0.04 | 0.30 | 0.14x |
| try | 1000000 | 0.59 | 0.59 | 1.00x |
| match | 1000000 | 3.62 | 1.57 | 2.31x |
| builtin_length | 1000000 | 0.05 | 0.29 | 0.16x |
| for_list | 1000000 | 0.46 | 0.39 | 1.17x |
