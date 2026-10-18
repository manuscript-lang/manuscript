Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 2.29 | 3.39 | 0.68x |
| read_line | 200000 | 59.39 | 63.82 | 0.93x |
| map_put_get_8k | 16000 | 34.84 | 31.54 | 1.10x |
| int_eq | 10000000 | 1.01 | 0.96 | 1.06x |
| generic_call | 1000000 | 0.05 | 0.29 | 0.18x |
| method_call | 1000000 | 0.04 | 0.28 | 0.15x |
| try | 1000000 | 0.64 | 0.56 | 1.13x |
| match | 1000000 | 3.47 | 1.59 | 2.19x |
| builtin_length | 1000000 | 0.05 | 0.29 | 0.16x |
| for_list | 1000000 | 0.40 | 0.36 | 1.11x |
