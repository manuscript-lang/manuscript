Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 3.59 | 2.86 | 1.26x |
| read_line | 200000 | 59.55 | 63.95 | 0.93x |
| map_put_get_8k | 16000 | 33.11 | 32.25 | 1.03x |
| int_eq | 10000000 | 1.04 | 0.98 | 1.06x |
| generic_call | 1000000 | 0.05 | 0.28 | 0.18x |
| method_call | 1000000 | 0.04 | 0.28 | 0.16x |
| try | 1000000 | 0.60 | 0.56 | 1.07x |
| match | 1000000 | 3.52 | 1.53 | 2.30x |
| builtin_length | 1000000 | 0.05 | 0.28 | 0.16x |
| for_list | 1000000 | 0.45 | 0.37 | 1.24x |
