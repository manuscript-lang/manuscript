Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 4.40 | 3.63 | 1.21x |
| read_line | 200000 | 86.66 | 68.56 | 1.26x |
| map_put_get_8k | 16000 | 50.48 | 34.34 | 1.47x |
| int_eq | 10000000 | 1.02 | 1.06 | 0.96x |
| generic_call | 1000000 | 0.34 | 0.28 | 1.21x |
| method_call | 1000000 | 0.94 | 0.30 | 3.13x |
| try | 1000000 | 0.84 | 0.59 | 1.44x |
| match | 1000000 | 4.55 | 1.73 | 2.63x |
| builtin_length | 1000000 | 0.66 | 0.29 | 2.26x |
| for_list | 1000000 | 0.47 | 0.40 | 1.15x |
