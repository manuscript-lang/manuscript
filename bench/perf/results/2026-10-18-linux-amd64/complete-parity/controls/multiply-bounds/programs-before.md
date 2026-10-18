Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 3.77 | 3.02 | 1.25x |
| read_line | 200000 | 85.39 | 71.19 | 1.20x |
| map_put_get_8k | 16000 | 53.32 | 33.55 | 1.59x |
| int_eq | 10000000 | 1.06 | 1.03 | 1.03x |
| generic_call | 1000000 | 0.35 | 0.30 | 1.19x |
| method_call | 1000000 | 0.99 | 0.29 | 3.41x |
| try | 1000000 | 0.84 | 0.59 | 1.41x |
| match | 1000000 | 4.54 | 1.64 | 2.78x |
| builtin_length | 1000000 | 0.64 | 0.29 | 2.22x |
| for_list | 1000000 | 0.46 | 0.39 | 1.18x |
