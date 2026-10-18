Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 3.66 | 2.83 | 1.29x |
| read_line | 200000 | 60.72 | 66.63 | 0.91x |
| map_put_get_8k | 16000 | 35.05 | 32.39 | 1.08x |
| int_eq | 10000000 | 1.02 | 0.99 | 1.03x |
| generic_call | 1000000 | 0.05 | 0.30 | 0.17x |
| method_call | 1000000 | 0.04 | 0.29 | 0.15x |
| try | 1000000 | 0.57 | 0.58 | 0.97x |
| match | 1000000 | 2.01 | 1.54 | 1.30x |
| builtin_length | 1000000 | 0.05 | 0.28 | 0.17x |
| for_list | 1000000 | 0.65 | 0.36 | 1.80x |
