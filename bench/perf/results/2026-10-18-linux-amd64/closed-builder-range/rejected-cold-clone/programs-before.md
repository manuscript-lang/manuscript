Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 3.54 | 3.09 | 1.14x |
| read_line | 200000 | 57.29 | 62.08 | 0.92x |
| map_put_get_8k | 16000 | 33.24 | 32.30 | 1.03x |
| int_eq | 10000000 | 1.03 | 0.98 | 1.05x |
| generic_call | 1000000 | 0.06 | 0.27 | 0.23x |
| method_call | 1000000 | 0.05 | 0.29 | 0.19x |
| try | 1000000 | 0.56 | 0.57 | 1.00x |
| match | 1000000 | 3.50 | 1.56 | 2.24x |
| builtin_length | 1000000 | 0.06 | 0.28 | 0.20x |
| for_list | 1000000 | 0.47 | 0.39 | 1.20x |
