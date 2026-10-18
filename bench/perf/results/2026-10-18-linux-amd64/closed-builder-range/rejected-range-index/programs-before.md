Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 3.67 | 3.00 | 1.22x |
| read_line | 200000 | 58.57 | 63.13 | 0.93x |
| map_put_get_8k | 16000 | 33.77 | 30.99 | 1.09x |
| int_eq | 10000000 | 1.03 | 0.95 | 1.08x |
| generic_call | 1000000 | 0.05 | 0.28 | 0.18x |
| method_call | 1000000 | 0.04 | 0.27 | 0.16x |
| try | 1000000 | 0.60 | 0.56 | 1.07x |
| match | 1000000 | 3.60 | 1.54 | 2.34x |
| builtin_length | 1000000 | 0.05 | 0.28 | 0.16x |
| for_list | 1000000 | 0.47 | 0.37 | 1.29x |
