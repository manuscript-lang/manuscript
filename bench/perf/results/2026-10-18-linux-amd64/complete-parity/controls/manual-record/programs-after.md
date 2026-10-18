Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 3.40 | 2.83 | 1.20x |
| read_line | 200000 | 79.47 | 64.54 | 1.23x |
| map_put_get_8k | 16000 | 44.60 | 32.08 | 1.39x |
| int_eq | 10000000 | 1.04 | 0.96 | 1.08x |
| generic_call | 1000000 | 0.61 | 0.28 | 2.16x |
| method_call | 1000000 | 0.32 | 0.29 | 1.10x |
| try | 1000000 | 0.79 | 0.56 | 1.41x |
| match | 1000000 | 3.43 | 1.57 | 2.18x |
| builtin_length | 1000000 | 0.59 | 0.27 | 2.18x |
| for_list | 1000000 | 0.43 | 0.37 | 1.15x |
