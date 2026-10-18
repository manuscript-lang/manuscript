Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 3.22 | 2.99 | 1.08x |
| read_line | 200000 | 57.96 | 64.48 | 0.90x |
| map_put_get_8k | 16000 | 31.95 | 31.16 | 1.03x |
| int_eq | 10000000 | 0.99 | 0.95 | 1.04x |
| generic_call | 1000000 | 0.05 | 0.27 | 0.19x |
| method_call | 1000000 | 0.04 | 0.28 | 0.16x |
| try | 1000000 | 0.58 | 0.56 | 1.05x |
| match | 1000000 | 2.04 | 1.51 | 1.35x |
| builtin_length | 1000000 | 0.05 | 0.27 | 0.17x |
| for_list | 1000000 | 0.36 | 0.38 | 0.96x |
