Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 3.32 | 2.64 | 1.26x |
| read_line | 200000 | 58.06 | 63.95 | 0.91x |
| map_put_get_8k | 16000 | 32.82 | 32.79 | 1.00x |
| int_eq | 10000000 | 1.02 | 0.95 | 1.07x |
| generic_call | 1000000 | 0.05 | 0.27 | 0.19x |
| method_call | 1000000 | 0.04 | 0.29 | 0.15x |
| try | 1000000 | 0.59 | 0.57 | 1.03x |
| match | 1000000 | 3.47 | 1.50 | 2.31x |
| builtin_length | 1000000 | 0.05 | 0.27 | 0.17x |
| for_list | 1000000 | 0.44 | 0.33 | 1.34x |
