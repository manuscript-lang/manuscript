Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 3.55 | 2.99 | 1.19x |
| read_line | 200000 | 59.65 | 68.38 | 0.87x |
| map_put_get_8k | 16000 | 32.84 | 32.85 | 1.00x |
| int_eq | 10000000 | 1.05 | 0.99 | 1.06x |
| generic_call | 1000000 | 0.05 | 0.29 | 0.18x |
| method_call | 1000000 | 0.04 | 0.29 | 0.15x |
| try | 1000000 | 0.61 | 0.57 | 1.06x |
| match | 1000000 | 2.00 | 1.61 | 1.24x |
| builtin_length | 1000000 | 0.05 | 0.28 | 0.17x |
| for_list | 1000000 | 0.40 | 0.38 | 1.05x |
