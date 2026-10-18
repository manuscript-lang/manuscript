Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 2.48 | 3.08 | 0.80x |
| read_line | 200000 | 62.91 | 66.38 | 0.95x |
| map_put_get_8k | 16000 | 35.18 | 34.22 | 1.03x |
| int_eq | 10000000 | 1.05 | 1.05 | 1.01x |
| generic_call | 1000000 | 0.05 | 0.28 | 0.18x |
| method_call | 1000000 | 0.04 | 0.28 | 0.15x |
| try | 1000000 | 0.64 | 0.58 | 1.11x |
| match | 1000000 | 3.51 | 1.59 | 2.21x |
| builtin_length | 1000000 | 0.05 | 0.28 | 0.16x |
| for_list | 1000000 | 0.41 | 0.38 | 1.07x |
