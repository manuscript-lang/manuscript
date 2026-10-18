Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 3.81 | 2.85 | 1.34x |
| read_line | 200000 | 59.41 | 63.66 | 0.93x |
| map_put_get_8k | 16000 | 34.94 | 32.08 | 1.09x |
| int_eq | 10000000 | 1.02 | 1.03 | 0.99x |
| generic_call | 1000000 | 0.32 | 0.27 | 1.17x |
| method_call | 1000000 | 0.64 | 0.28 | 2.31x |
| try | 1000000 | 0.62 | 0.56 | 1.10x |
| match | 1000000 | 3.47 | 1.57 | 2.22x |
| builtin_length | 1000000 | 0.33 | 0.27 | 1.20x |
| for_list | 1000000 | 0.45 | 0.38 | 1.19x |
