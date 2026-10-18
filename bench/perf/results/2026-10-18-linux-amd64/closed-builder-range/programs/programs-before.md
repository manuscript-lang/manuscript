Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 3.66 | 3.53 | 1.04x |
| read_line | 200000 | 60.83 | 63.73 | 0.95x |
| map_put_get_8k | 16000 | 33.07 | 30.95 | 1.07x |
| int_eq | 10000000 | 1.05 | 0.99 | 1.06x |
| generic_call | 1000000 | 0.05 | 0.27 | 0.19x |
| method_call | 1000000 | 0.04 | 0.28 | 0.16x |
| try | 1000000 | 0.59 | 0.56 | 1.05x |
| match | 1000000 | 3.53 | 1.58 | 2.23x |
| builtin_length | 1000000 | 0.05 | 0.28 | 0.16x |
| for_list | 1000000 | 0.44 | 0.34 | 1.29x |
