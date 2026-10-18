Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 3.52 | 2.93 | 1.20x |
| read_line | 200000 | 66.13 | 67.24 | 0.98x |
| map_put_get_8k | 16000 | 36.00 | 34.01 | 1.06x |
| int_eq | 10000000 | 1.08 | 1.01 | 1.07x |
| generic_call | 1000000 | 0.64 | 0.27 | 2.36x |
| method_call | 1000000 | 0.33 | 0.29 | 1.14x |
| try | 1000000 | 0.80 | 0.56 | 1.43x |
| match | 1000000 | 3.52 | 1.59 | 2.21x |
| builtin_length | 1000000 | 0.33 | 0.28 | 1.18x |
| for_list | 1000000 | 0.46 | 0.40 | 1.16x |
