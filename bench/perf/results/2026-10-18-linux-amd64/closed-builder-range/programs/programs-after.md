Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 2.13 | 3.53 | 0.60x |
| read_line | 200000 | 58.75 | 63.73 | 0.92x |
| map_put_get_8k | 16000 | 34.58 | 30.95 | 1.12x |
| int_eq | 10000000 | 1.03 | 0.99 | 1.05x |
| generic_call | 1000000 | 0.05 | 0.27 | 0.19x |
| method_call | 1000000 | 0.04 | 0.28 | 0.16x |
| try | 1000000 | 0.65 | 0.56 | 1.15x |
| match | 1000000 | 3.46 | 1.58 | 2.19x |
| builtin_length | 1000000 | 0.05 | 0.28 | 0.17x |
| for_list | 1000000 | 0.38 | 0.34 | 1.11x |
