Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 7.09 | 2.81 | 2.53x |
| read_line | 200000 | 81.89 | 62.99 | 1.30x |
| map_put_get_8k | 16000 | 64.51 | 31.93 | 2.02x |
| int_eq | 10000000 | 1.24 | 0.98 | 1.26x |
| generic_call | 1000000 | 0.88 | 0.28 | 3.11x |
| method_call | 1000000 | 2.27 | 0.29 | 7.84x |
| try | 1000000 | 3.63 | 0.56 | 6.53x |
| match | 1000000 | 6.39 | 1.57 | 4.06x |
| builtin_length | 1000000 | 1.22 | 0.28 | 4.31x |
| for_list | 1000000 | 0.92 | 0.41 | 2.26x |
