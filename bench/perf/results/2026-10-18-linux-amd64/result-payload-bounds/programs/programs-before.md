Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 3.22 | 2.81 | 1.15x |
| read_line | 200000 | 56.16 | 63.12 | 0.89x |
| map_put_get_8k | 16000 | 32.53 | 31.64 | 1.03x |
| int_eq | 10000000 | 1.01 | 0.97 | 1.05x |
| generic_call | 1000000 | 0.31 | 0.27 | 1.12x |
| method_call | 1000000 | 0.61 | 0.28 | 2.20x |
| try | 1000000 | 1.16 | 0.56 | 2.06x |
| match | 1000000 | 3.61 | 1.51 | 2.39x |
| builtin_length | 1000000 | 0.62 | 0.28 | 2.25x |
| for_list | 1000000 | 0.62 | 0.39 | 1.60x |
