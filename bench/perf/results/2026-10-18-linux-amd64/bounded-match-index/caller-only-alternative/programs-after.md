Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 2.12 | 3.13 | 0.68x |
| read_line | 200000 | 57.91 | 63.02 | 0.92x |
| map_put_get_8k | 16000 | 33.60 | 31.58 | 1.06x |
| int_eq | 10000000 | 1.04 | 0.98 | 1.06x |
| generic_call | 1000000 | 0.05 | 0.27 | 0.19x |
| method_call | 1000000 | 0.04 | 0.29 | 0.15x |
| try | 1000000 | 0.63 | 0.57 | 1.11x |
| match | 1000000 | 3.31 | 1.55 | 2.14x |
| builtin_length | 1000000 | 0.05 | 0.28 | 0.17x |
| for_list | 1000000 | 0.35 | 0.39 | 0.89x |
