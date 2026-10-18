Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 3.56 | 2.93 | 1.21x |
| read_line | 200000 | 85.73 | 65.26 | 1.31x |
| map_put_get_8k | 16000 | 45.59 | 33.82 | 1.35x |
| int_eq | 10000000 | 1.01 | 0.98 | 1.03x |
| generic_call | 1000000 | 0.32 | 0.27 | 1.17x |
| method_call | 1000000 | 0.65 | 0.29 | 2.27x |
| try | 1000000 | 1.18 | 0.59 | 2.02x |
| match | 1000000 | 3.55 | 1.54 | 2.31x |
| builtin_length | 1000000 | 0.67 | 0.29 | 2.34x |
| for_list | 1000000 | 0.67 | 0.39 | 1.72x |
