Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 3.82 | 3.36 | 1.14x |
| read_line | 200000 | 78.08 | 63.96 | 1.22x |
| map_put_get_8k | 16000 | 48.23 | 31.72 | 1.52x |
| int_eq | 10000000 | 1.00 | 0.97 | 1.03x |
| generic_call | 1000000 | 0.32 | 0.28 | 1.16x |
| method_call | 1000000 | 0.86 | 0.29 | 3.03x |
| try | 1000000 | 0.78 | 0.57 | 1.37x |
| match | 1000000 | 4.19 | 1.60 | 2.62x |
| builtin_length | 1000000 | 0.60 | 0.28 | 2.15x |
| for_list | 1000000 | 0.43 | 0.37 | 1.16x |
