Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 3.52 | 2.94 | 1.19x |
| read_line | 200000 | 79.99 | 66.30 | 1.21x |
| map_put_get_8k | 16000 | 65.04 | 31.30 | 2.08x |
| int_eq | 10000000 | 1.23 | 0.98 | 1.26x |
| generic_call | 1000000 | 0.63 | 0.27 | 2.30x |
| method_call | 1000000 | 2.30 | 0.29 | 7.85x |
| try | 1000000 | 2.31 | 0.56 | 4.15x |
| match | 1000000 | 4.30 | 1.58 | 2.72x |
| builtin_length | 1000000 | 0.61 | 0.30 | 2.06x |
| for_list | 1000000 | 1.25 | 0.34 | 3.62x |
