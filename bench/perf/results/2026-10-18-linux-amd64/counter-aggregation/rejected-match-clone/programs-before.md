Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 3.19 | 2.86 | 1.11x |
| read_line | 200000 | 59.45 | 62.16 | 0.96x |
| map_put_get_8k | 16000 | 33.29 | 32.15 | 1.04x |
| int_eq | 10000000 | 1.02 | 0.98 | 1.04x |
| generic_call | 1000000 | 0.05 | 0.28 | 0.18x |
| method_call | 1000000 | 0.04 | 0.29 | 0.15x |
| try | 1000000 | 0.57 | 0.57 | 1.01x |
| match | 1000000 | 3.56 | 1.54 | 2.31x |
| builtin_length | 1000000 | 0.05 | 0.27 | 0.17x |
| for_list | 1000000 | 0.44 | 0.37 | 1.21x |
