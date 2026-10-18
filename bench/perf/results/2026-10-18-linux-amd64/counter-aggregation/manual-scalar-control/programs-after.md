Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 3.88 | 2.92 | 1.33x |
| read_line | 200000 | 57.85 | 64.82 | 0.89x |
| map_put_get_8k | 16000 | 32.66 | 33.89 | 0.96x |
| int_eq | 10000000 | 1.01 | 1.00 | 1.01x |
| generic_call | 1000000 | 0.05 | 0.28 | 0.18x |
| method_call | 1000000 | 0.31 | 0.29 | 1.07x |
| try | 1000000 | 0.57 | 0.57 | 1.01x |
| match | 1000000 | 3.49 | 1.52 | 2.29x |
| builtin_length | 1000000 | 0.05 | 0.28 | 0.16x |
| for_list | 1000000 | 0.45 | 0.37 | 1.21x |
