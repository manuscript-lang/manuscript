Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 3.48 | 3.51 | 0.99x |
| read_line | 200000 | 60.63 | 67.75 | 0.90x |
| map_put_get_8k | 16000 | 34.86 | 33.92 | 1.03x |
| int_eq | 10000000 | 1.08 | 1.01 | 1.07x |
| generic_call | 1000000 | 0.05 | 0.28 | 0.18x |
| method_call | 1000000 | 0.04 | 0.29 | 0.15x |
| try | 1000000 | 0.60 | 0.58 | 1.05x |
| match | 1000000 | 3.72 | 1.58 | 2.35x |
| builtin_length | 1000000 | 0.05 | 0.28 | 0.17x |
| for_list | 1000000 | 0.47 | 0.38 | 1.23x |
