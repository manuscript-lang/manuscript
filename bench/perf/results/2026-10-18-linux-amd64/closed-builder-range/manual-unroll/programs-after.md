Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 3.42 | 2.86 | 1.20x |
| read_line | 200000 | 56.50 | 64.83 | 0.87x |
| map_put_get_8k | 16000 | 34.00 | 31.33 | 1.09x |
| int_eq | 10000000 | 1.02 | 0.97 | 1.05x |
| generic_call | 1000000 | 0.05 | 0.28 | 0.18x |
| method_call | 1000000 | 0.04 | 0.28 | 0.16x |
| try | 1000000 | 0.56 | 0.58 | 0.96x |
| match | 1000000 | 3.40 | 1.54 | 2.21x |
| builtin_length | 1000000 | 0.05 | 0.28 | 0.16x |
| for_list | 1000000 | 0.40 | 0.36 | 1.10x |
