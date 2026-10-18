Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 3.56 | 2.68 | 1.33x |
| read_line | 200000 | 85.35 | 63.08 | 1.35x |
| map_put_get_8k | 16000 | 67.77 | 34.20 | 1.98x |
| int_eq | 10000000 | 1.24 | 0.99 | 1.25x |
| generic_call | 1000000 | 0.89 | 0.28 | 3.15x |
| method_call | 1000000 | 2.36 | 0.29 | 8.23x |
| try | 1000000 | 2.84 | 0.56 | 5.03x |
| match | 1000000 | 4.77 | 1.58 | 3.03x |
| builtin_length | 1000000 | 0.93 | 0.28 | 3.28x |
| for_list | 1000000 | 0.92 | 0.39 | 2.40x |
