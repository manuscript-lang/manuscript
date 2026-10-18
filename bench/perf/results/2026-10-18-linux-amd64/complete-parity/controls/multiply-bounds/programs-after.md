Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 3.97 | 3.02 | 1.32x |
| read_line | 200000 | 91.38 | 71.19 | 1.28x |
| map_put_get_8k | 16000 | 47.29 | 33.55 | 1.41x |
| int_eq | 10000000 | 1.08 | 1.03 | 1.05x |
| generic_call | 1000000 | 0.34 | 0.30 | 1.15x |
| method_call | 1000000 | 0.96 | 0.29 | 3.29x |
| try | 1000000 | 0.82 | 0.59 | 1.39x |
| match | 1000000 | 4.45 | 1.64 | 2.72x |
| builtin_length | 1000000 | 0.64 | 0.29 | 2.22x |
| for_list | 1000000 | 0.47 | 0.39 | 1.19x |
