Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 4.68 | 3.35 | 1.40x |
| read_line | 200000 | 68.34 | 74.16 | 0.92x |
| map_put_get_8k | 16000 | 36.03 | 36.86 | 0.98x |
| int_eq | 10000000 | 1.07 | 1.12 | 0.95x |
| generic_call | 1000000 | 0.38 | 0.30 | 1.28x |
| method_call | 1000000 | 0.66 | 0.34 | 1.95x |
| try | 1000000 | 1.22 | 0.63 | 1.95x |
| match | 1000000 | 3.82 | 1.79 | 2.14x |
| builtin_length | 1000000 | 0.68 | 0.29 | 2.33x |
| for_list | 1000000 | 0.66 | 0.35 | 1.88x |
