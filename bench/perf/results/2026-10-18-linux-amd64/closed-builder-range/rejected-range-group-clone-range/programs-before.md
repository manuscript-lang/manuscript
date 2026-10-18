Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 3.65 | 2.99 | 1.22x |
| read_line | 200000 | 59.74 | 68.38 | 0.87x |
| map_put_get_8k | 16000 | 33.44 | 32.85 | 1.02x |
| int_eq | 10000000 | 1.07 | 0.99 | 1.08x |
| generic_call | 1000000 | 0.05 | 0.29 | 0.18x |
| method_call | 1000000 | 0.04 | 0.29 | 0.15x |
| try | 1000000 | 0.59 | 0.57 | 1.02x |
| match | 1000000 | 3.72 | 1.61 | 2.31x |
| builtin_length | 1000000 | 0.05 | 0.28 | 0.16x |
| for_list | 1000000 | 0.44 | 0.38 | 1.15x |
