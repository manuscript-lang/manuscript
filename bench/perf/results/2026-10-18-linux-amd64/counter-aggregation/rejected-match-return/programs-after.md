Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 3.72 | 3.28 | 1.13x |
| read_line | 200000 | 56.31 | 62.11 | 0.91x |
| map_put_get_8k | 16000 | 34.47 | 35.14 | 0.98x |
| int_eq | 10000000 | 1.02 | 0.97 | 1.05x |
| generic_call | 1000000 | 0.05 | 0.28 | 0.18x |
| method_call | 1000000 | 0.04 | 0.29 | 0.15x |
| try | 1000000 | 0.59 | 0.57 | 1.03x |
| match | 1000000 | 3.47 | 1.54 | 2.26x |
| builtin_length | 1000000 | 0.05 | 0.28 | 0.16x |
| for_list | 1000000 | 0.43 | 0.36 | 1.20x |
