Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 2.17 | 3.03 | 0.72x |
| read_line | 200000 | 57.27 | 61.81 | 0.93x |
| map_put_get_8k | 16000 | 33.57 | 31.19 | 1.08x |
| int_eq | 10000000 | 1.00 | 0.95 | 1.05x |
| generic_call | 1000000 | 0.05 | 0.27 | 0.19x |
| method_call | 1000000 | 0.04 | 0.28 | 0.16x |
| try | 1000000 | 0.65 | 0.56 | 1.16x |
| match | 1000000 | 3.39 | 1.54 | 2.20x |
| builtin_length | 1000000 | 0.05 | 0.28 | 0.17x |
| for_list | 1000000 | 0.62 | 0.38 | 1.66x |
