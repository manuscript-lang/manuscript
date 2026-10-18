Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 3.55 | 2.86 | 1.24x |
| read_line | 200000 | 87.16 | 66.93 | 1.30x |
| map_put_get_8k | 16000 | 68.29 | 32.18 | 2.12x |
| int_eq | 10000000 | 1.14 | 0.99 | 1.15x |
| generic_call | 1000000 | 0.90 | 0.28 | 3.24x |
| method_call | 1000000 | 0.89 | 0.29 | 3.10x |
| try | 1000000 | 0.83 | 0.59 | 1.42x |
| match | 1000000 | 4.36 | 1.55 | 2.82x |
| builtin_length | 1000000 | 0.90 | 0.28 | 3.19x |
| for_list | 1000000 | 0.96 | 0.41 | 2.32x |
