Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 3.94 | 3.40 | 1.16x |
| read_line | 200000 | 85.72 | 67.01 | 1.28x |
| map_put_get_8k | 16000 | 62.72 | 31.73 | 1.98x |
| int_eq | 10000000 | 1.05 | 1.01 | 1.04x |
| generic_call | 1000000 | 0.33 | 0.29 | 1.14x |
| method_call | 1000000 | 0.89 | 0.30 | 2.97x |
| try | 1000000 | 0.79 | 0.56 | 1.40x |
| match | 1000000 | 4.35 | 1.62 | 2.69x |
| builtin_length | 1000000 | 0.87 | 0.29 | 3.05x |
| for_list | 1000000 | 0.96 | 0.39 | 2.49x |
