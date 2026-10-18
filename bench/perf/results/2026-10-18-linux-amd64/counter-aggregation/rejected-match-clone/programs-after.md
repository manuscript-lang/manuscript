Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 3.29 | 2.86 | 1.15x |
| read_line | 200000 | 57.77 | 62.16 | 0.93x |
| map_put_get_8k | 16000 | 32.42 | 32.15 | 1.01x |
| int_eq | 10000000 | 1.01 | 0.98 | 1.03x |
| generic_call | 1000000 | 0.05 | 0.28 | 0.18x |
| method_call | 1000000 | 0.04 | 0.29 | 0.15x |
| try | 1000000 | 0.57 | 0.57 | 1.00x |
| match | 1000000 | 2.56 | 1.54 | 1.66x |
| builtin_length | 1000000 | 0.05 | 0.27 | 0.17x |
| for_list | 1000000 | 0.62 | 0.37 | 1.70x |
