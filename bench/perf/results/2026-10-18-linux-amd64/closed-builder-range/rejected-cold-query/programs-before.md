Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 3.75 | 2.93 | 1.28x |
| read_line | 200000 | 58.52 | 63.16 | 0.93x |
| map_put_get_8k | 16000 | 32.60 | 33.50 | 0.97x |
| int_eq | 10000000 | 1.01 | 0.96 | 1.04x |
| generic_call | 1000000 | 0.05 | 0.27 | 0.19x |
| method_call | 1000000 | 0.04 | 0.29 | 0.15x |
| try | 1000000 | 0.57 | 0.57 | 0.99x |
| match | 1000000 | 3.51 | 1.56 | 2.26x |
| builtin_length | 1000000 | 0.05 | 0.29 | 0.16x |
| for_list | 1000000 | 0.44 | 0.40 | 1.11x |
