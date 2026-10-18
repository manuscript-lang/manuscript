Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 2.27 | 2.93 | 0.77x |
| read_line | 200000 | 58.00 | 64.17 | 0.90x |
| map_put_get_8k | 16000 | 32.34 | 31.27 | 1.03x |
| int_eq | 10000000 | 1.02 | 0.97 | 1.06x |
| generic_call | 1000000 | 0.05 | 0.28 | 0.18x |
| method_call | 1000000 | 0.04 | 0.28 | 0.15x |
| try | 1000000 | 0.63 | 0.57 | 1.10x |
| match | 1000000 | 2.23 | 1.55 | 1.44x |
| builtin_length | 1000000 | 0.05 | 0.28 | 0.16x |
| for_list | 1000000 | 0.37 | 0.34 | 1.10x |
