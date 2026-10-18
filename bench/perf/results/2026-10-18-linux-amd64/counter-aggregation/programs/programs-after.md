Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 3.65 | 2.85 | 1.28x |
| read_line | 200000 | 61.08 | 63.66 | 0.96x |
| map_put_get_8k | 16000 | 35.14 | 32.08 | 1.10x |
| int_eq | 10000000 | 1.03 | 1.03 | 1.00x |
| generic_call | 1000000 | 0.05 | 0.27 | 0.19x |
| method_call | 1000000 | 0.04 | 0.28 | 0.15x |
| try | 1000000 | 0.58 | 0.56 | 1.03x |
| match | 1000000 | 3.62 | 1.57 | 2.31x |
| builtin_length | 1000000 | 0.05 | 0.27 | 0.17x |
| for_list | 1000000 | 0.43 | 0.38 | 1.13x |
