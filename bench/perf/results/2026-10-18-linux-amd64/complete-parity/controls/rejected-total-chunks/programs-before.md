Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 3.29 | 2.83 | 1.16x |
| read_line | 200000 | 57.40 | 62.90 | 0.91x |
| map_put_get_8k | 16000 | 32.72 | 31.71 | 1.03x |
| int_eq | 10000000 | 1.05 | 0.97 | 1.08x |
| generic_call | 1000000 | 0.60 | 0.28 | 2.19x |
| method_call | 1000000 | 0.31 | 0.28 | 1.11x |
| try | 1000000 | 0.80 | 0.57 | 1.41x |
| match | 1000000 | 3.32 | 1.54 | 2.16x |
| builtin_length | 1000000 | 0.33 | 0.28 | 1.17x |
| for_list | 1000000 | 0.44 | 0.39 | 1.15x |
