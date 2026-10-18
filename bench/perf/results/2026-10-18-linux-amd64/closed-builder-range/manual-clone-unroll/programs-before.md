Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 3.49 | 2.99 | 1.17x |
| read_line | 200000 | 57.98 | 64.48 | 0.90x |
| map_put_get_8k | 16000 | 32.73 | 31.16 | 1.05x |
| int_eq | 10000000 | 1.02 | 0.95 | 1.07x |
| generic_call | 1000000 | 0.05 | 0.27 | 0.19x |
| method_call | 1000000 | 0.04 | 0.28 | 0.16x |
| try | 1000000 | 0.57 | 0.56 | 1.03x |
| match | 1000000 | 3.48 | 1.51 | 2.31x |
| builtin_length | 1000000 | 0.05 | 0.27 | 0.17x |
| for_list | 1000000 | 0.45 | 0.38 | 1.18x |
