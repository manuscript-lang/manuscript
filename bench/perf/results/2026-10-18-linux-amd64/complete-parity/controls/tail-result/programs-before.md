Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 3.98 | 2.86 | 1.39x |
| read_line | 200000 | 85.79 | 66.93 | 1.28x |
| map_put_get_8k | 16000 | 63.73 | 32.18 | 1.98x |
| int_eq | 10000000 | 1.09 | 0.99 | 1.10x |
| generic_call | 1000000 | 0.90 | 0.28 | 3.23x |
| method_call | 1000000 | 2.63 | 0.29 | 9.14x |
| try | 1000000 | 2.64 | 0.59 | 4.49x |
| match | 1000000 | 4.24 | 1.55 | 2.74x |
| builtin_length | 1000000 | 0.86 | 0.28 | 3.05x |
| for_list | 1000000 | 0.94 | 0.41 | 2.28x |
