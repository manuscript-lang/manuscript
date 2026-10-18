Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 4.66 | 3.40 | 1.37x |
| read_line | 200000 | 87.66 | 67.01 | 1.31x |
| map_put_get_8k | 16000 | 67.73 | 31.73 | 2.13x |
| int_eq | 10000000 | 1.15 | 1.01 | 1.13x |
| generic_call | 1000000 | 0.89 | 0.29 | 3.07x |
| method_call | 1000000 | 0.92 | 0.30 | 3.06x |
| try | 1000000 | 0.80 | 0.56 | 1.42x |
| match | 1000000 | 4.29 | 1.62 | 2.66x |
| builtin_length | 1000000 | 0.90 | 0.29 | 3.17x |
| for_list | 1000000 | 0.95 | 0.39 | 2.45x |
