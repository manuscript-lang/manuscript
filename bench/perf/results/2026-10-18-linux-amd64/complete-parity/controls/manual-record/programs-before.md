Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 3.29 | 2.83 | 1.16x |
| read_line | 200000 | 79.70 | 64.54 | 1.24x |
| map_put_get_8k | 16000 | 47.25 | 32.08 | 1.47x |
| int_eq | 10000000 | 1.05 | 0.96 | 1.10x |
| generic_call | 1000000 | 0.64 | 0.28 | 2.27x |
| method_call | 1000000 | 0.88 | 0.29 | 3.05x |
| try | 1000000 | 1.18 | 0.56 | 2.09x |
| match | 1000000 | 3.46 | 1.57 | 2.20x |
| builtin_length | 1000000 | 0.33 | 0.27 | 1.22x |
| for_list | 1000000 | 0.63 | 0.37 | 1.69x |
