Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 3.57 | 2.83 | 1.26x |
| read_line | 200000 | 59.21 | 66.63 | 0.89x |
| map_put_get_8k | 16000 | 33.29 | 32.39 | 1.03x |
| int_eq | 10000000 | 0.99 | 0.99 | 1.00x |
| generic_call | 1000000 | 0.05 | 0.30 | 0.17x |
| method_call | 1000000 | 0.04 | 0.29 | 0.15x |
| try | 1000000 | 0.58 | 0.58 | 1.00x |
| match | 1000000 | 3.48 | 1.54 | 2.26x |
| builtin_length | 1000000 | 0.05 | 0.28 | 0.17x |
| for_list | 1000000 | 0.43 | 0.36 | 1.20x |
