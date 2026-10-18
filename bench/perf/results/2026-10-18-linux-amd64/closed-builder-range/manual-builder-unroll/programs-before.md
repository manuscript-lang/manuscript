Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 3.54 | 2.80 | 1.26x |
| read_line | 200000 | 59.33 | 63.82 | 0.93x |
| map_put_get_8k | 16000 | 36.51 | 31.78 | 1.15x |
| int_eq | 10000000 | 1.05 | 0.96 | 1.09x |
| generic_call | 1000000 | 0.05 | 0.27 | 0.19x |
| method_call | 1000000 | 0.04 | 0.28 | 0.15x |
| try | 1000000 | 0.57 | 0.59 | 0.97x |
| match | 1000000 | 3.65 | 1.54 | 2.37x |
| builtin_length | 1000000 | 0.05 | 0.28 | 0.16x |
| for_list | 1000000 | 0.44 | 0.33 | 1.32x |
