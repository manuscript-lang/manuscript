Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 3.34 | 2.81 | 1.19x |
| read_line | 200000 | 81.32 | 62.99 | 1.29x |
| map_put_get_8k | 16000 | 64.61 | 31.93 | 2.02x |
| int_eq | 10000000 | 1.26 | 0.98 | 1.29x |
| generic_call | 1000000 | 0.90 | 0.28 | 3.20x |
| method_call | 1000000 | 2.37 | 0.29 | 8.18x |
| try | 1000000 | 2.74 | 0.56 | 4.94x |
| match | 1000000 | 4.82 | 1.57 | 3.07x |
| builtin_length | 1000000 | 0.92 | 0.28 | 3.25x |
| for_list | 1000000 | 0.95 | 0.41 | 2.31x |
