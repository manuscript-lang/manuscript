Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 3.31 | 2.68 | 1.23x |
| read_line | 200000 | 82.36 | 63.08 | 1.31x |
| map_put_get_8k | 16000 | 68.64 | 34.20 | 2.01x |
| int_eq | 10000000 | 1.24 | 0.99 | 1.24x |
| generic_call | 1000000 | 0.96 | 0.28 | 3.39x |
| method_call | 1000000 | 2.34 | 0.29 | 8.15x |
| try | 1000000 | 3.57 | 0.56 | 6.33x |
| match | 1000000 | 4.70 | 1.58 | 2.98x |
| builtin_length | 1000000 | 0.93 | 0.28 | 3.28x |
| for_list | 1000000 | 0.94 | 0.39 | 2.45x |
