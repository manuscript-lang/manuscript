Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 3.46 | 3.36 | 1.03x |
| read_line | 200000 | 79.51 | 63.96 | 1.24x |
| map_put_get_8k | 16000 | 47.20 | 31.72 | 1.49x |
| int_eq | 10000000 | 1.00 | 0.97 | 1.03x |
| generic_call | 1000000 | 0.32 | 0.28 | 1.16x |
| method_call | 1000000 | 0.87 | 0.29 | 3.04x |
| try | 1000000 | 0.79 | 0.57 | 1.38x |
| match | 1000000 | 4.22 | 1.60 | 2.64x |
| builtin_length | 1000000 | 0.86 | 0.28 | 3.10x |
| for_list | 1000000 | 0.90 | 0.37 | 2.44x |
