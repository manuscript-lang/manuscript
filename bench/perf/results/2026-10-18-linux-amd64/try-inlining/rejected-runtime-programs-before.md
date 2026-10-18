Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 3.63 | 3.18 | 1.14x |
| read_line | 200000 | 81.67 | 61.78 | 1.32x |
| map_put_get_8k | 16000 | 64.24 | 32.05 | 2.00x |
| int_eq | 10000000 | 1.19 | 0.96 | 1.24x |
| generic_call | 1000000 | 0.89 | 0.28 | 3.23x |
| method_call | 1000000 | 2.32 | 0.28 | 8.18x |
| try | 1000000 | 3.57 | 0.56 | 6.37x |
| match | 1000000 | 4.67 | 1.54 | 3.03x |
| builtin_length | 1000000 | 0.93 | 0.27 | 3.45x |
| for_list | 1000000 | 0.92 | 0.37 | 2.46x |
