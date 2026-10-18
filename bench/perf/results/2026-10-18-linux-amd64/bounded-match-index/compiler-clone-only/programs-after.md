Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 2.22 | 3.39 | 0.65x |
| read_line | 200000 | 58.88 | 63.82 | 0.92x |
| map_put_get_8k | 16000 | 33.23 | 31.54 | 1.05x |
| int_eq | 10000000 | 1.03 | 0.96 | 1.07x |
| generic_call | 1000000 | 0.05 | 0.29 | 0.18x |
| method_call | 1000000 | 0.04 | 0.28 | 0.15x |
| try | 1000000 | 0.59 | 0.56 | 1.05x |
| match | 1000000 | 2.20 | 1.59 | 1.39x |
| builtin_length | 1000000 | 0.05 | 0.29 | 0.16x |
| for_list | 1000000 | 0.37 | 0.36 | 1.04x |
