Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 3.39 | 2.93 | 1.16x |
| read_line | 200000 | 81.78 | 65.26 | 1.25x |
| map_put_get_8k | 16000 | 47.76 | 33.82 | 1.41x |
| int_eq | 10000000 | 1.01 | 0.98 | 1.03x |
| generic_call | 1000000 | 0.62 | 0.27 | 2.28x |
| method_call | 1000000 | 0.90 | 0.29 | 3.16x |
| try | 1000000 | 1.18 | 0.59 | 2.02x |
| match | 1000000 | 3.61 | 1.54 | 2.35x |
| builtin_length | 1000000 | 0.31 | 0.29 | 1.08x |
| for_list | 1000000 | 0.66 | 0.39 | 1.71x |
