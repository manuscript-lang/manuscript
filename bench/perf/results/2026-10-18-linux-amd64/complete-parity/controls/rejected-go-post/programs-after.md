Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 3.18 | 2.69 | 1.18x |
| read_line | 200000 | 58.33 | 63.11 | 0.92x |
| map_put_get_8k | 16000 | 32.21 | 31.38 | 1.03x |
| int_eq | 10000000 | 1.01 | 0.97 | 1.05x |
| generic_call | 1000000 | 0.61 | 0.28 | 2.16x |
| method_call | 1000000 | 0.32 | 0.29 | 1.12x |
| try | 1000000 | 0.80 | 0.56 | 1.43x |
| match | 1000000 | 3.42 | 1.54 | 2.22x |
| builtin_length | 1000000 | 0.33 | 0.28 | 1.18x |
| for_list | 1000000 | 0.45 | 0.37 | 1.21x |
