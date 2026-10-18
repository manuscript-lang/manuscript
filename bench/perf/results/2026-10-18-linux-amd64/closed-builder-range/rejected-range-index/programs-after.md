Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 3.45 | 3.00 | 1.15x |
| read_line | 200000 | 58.81 | 63.13 | 0.93x |
| map_put_get_8k | 16000 | 33.20 | 30.99 | 1.07x |
| int_eq | 10000000 | 1.03 | 0.95 | 1.08x |
| generic_call | 1000000 | 0.05 | 0.28 | 0.18x |
| method_call | 1000000 | 0.04 | 0.27 | 0.16x |
| try | 1000000 | 0.58 | 0.56 | 1.04x |
| match | 1000000 | 3.47 | 1.54 | 2.26x |
| builtin_length | 1000000 | 0.05 | 0.28 | 0.16x |
| for_list | 1000000 | 0.48 | 0.37 | 1.30x |
