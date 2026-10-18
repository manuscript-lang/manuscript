Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 3.72 | 3.63 | 1.03x |
| read_line | 200000 | 61.80 | 67.67 | 0.91x |
| map_put_get_8k | 16000 | 34.02 | 33.62 | 1.01x |
| int_eq | 10000000 | 1.01 | 1.01 | 1.00x |
| generic_call | 1000000 | 0.05 | 0.30 | 0.17x |
| method_call | 1000000 | 0.04 | 0.30 | 0.14x |
| try | 1000000 | 0.58 | 0.59 | 0.99x |
| match | 1000000 | 3.64 | 1.57 | 2.32x |
| builtin_length | 1000000 | 0.05 | 0.29 | 0.16x |
| for_list | 1000000 | 0.46 | 0.39 | 1.18x |
