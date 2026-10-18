Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 3.57 | 3.58 | 1.00x |
| read_line | 200000 | 82.03 | 65.29 | 1.26x |
| map_put_get_8k | 16000 | 45.29 | 32.64 | 1.39x |
| int_eq | 10000000 | 1.02 | 0.98 | 1.03x |
| generic_call | 1000000 | 0.33 | 0.27 | 1.20x |
| method_call | 1000000 | 0.89 | 0.29 | 3.11x |
| try | 1000000 | 0.81 | 0.57 | 1.42x |
| match | 1000000 | 4.40 | 1.53 | 2.87x |
| builtin_length | 1000000 | 0.90 | 0.27 | 3.31x |
| for_list | 1000000 | 0.93 | 0.35 | 2.63x |
