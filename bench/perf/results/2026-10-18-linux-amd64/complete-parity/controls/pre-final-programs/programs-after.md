Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 3.48 | 3.06 | 1.14x |
| read_line | 200000 | 58.66 | 64.52 | 0.91x |
| map_put_get_8k | 16000 | 33.86 | 31.70 | 1.07x |
| int_eq | 10000000 | 1.04 | 0.98 | 1.06x |
| generic_call | 1000000 | 0.65 | 0.28 | 2.32x |
| method_call | 1000000 | 0.32 | 0.29 | 1.11x |
| try | 1000000 | 0.80 | 0.57 | 1.41x |
| match | 1000000 | 3.43 | 1.55 | 2.21x |
| builtin_length | 1000000 | 0.32 | 0.27 | 1.18x |
| for_list | 1000000 | 0.44 | 0.37 | 1.20x |
