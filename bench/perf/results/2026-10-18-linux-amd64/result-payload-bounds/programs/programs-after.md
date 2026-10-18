Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 3.36 | 2.81 | 1.20x |
| read_line | 200000 | 57.97 | 63.12 | 0.92x |
| map_put_get_8k | 16000 | 32.99 | 31.64 | 1.04x |
| int_eq | 10000000 | 1.02 | 0.97 | 1.05x |
| generic_call | 1000000 | 0.32 | 0.27 | 1.17x |
| method_call | 1000000 | 0.65 | 0.28 | 2.37x |
| try | 1000000 | 0.63 | 0.56 | 1.11x |
| match | 1000000 | 3.41 | 1.51 | 2.26x |
| builtin_length | 1000000 | 0.32 | 0.28 | 1.16x |
| for_list | 1000000 | 0.45 | 0.39 | 1.16x |
