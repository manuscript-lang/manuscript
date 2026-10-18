Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 3.58 | 2.87 | 1.25x |
| read_line | 200000 | 60.60 | 69.54 | 0.87x |
| map_put_get_8k | 16000 | 36.13 | 34.71 | 1.04x |
| int_eq | 10000000 | 1.03 | 1.01 | 1.02x |
| generic_call | 1000000 | 0.63 | 0.29 | 2.13x |
| method_call | 1000000 | 0.33 | 0.28 | 1.21x |
| try | 1000000 | 0.81 | 0.59 | 1.37x |
| match | 1000000 | 3.52 | 1.56 | 2.26x |
| builtin_length | 1000000 | 0.35 | 0.29 | 1.19x |
| for_list | 1000000 | 0.46 | 0.40 | 1.16x |
