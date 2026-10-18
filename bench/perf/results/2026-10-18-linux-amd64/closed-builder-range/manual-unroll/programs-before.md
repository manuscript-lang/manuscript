Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 3.70 | 2.86 | 1.29x |
| read_line | 200000 | 60.27 | 64.83 | 0.93x |
| map_put_get_8k | 16000 | 34.10 | 31.33 | 1.09x |
| int_eq | 10000000 | 1.04 | 0.97 | 1.07x |
| generic_call | 1000000 | 0.05 | 0.28 | 0.18x |
| method_call | 1000000 | 0.04 | 0.28 | 0.16x |
| try | 1000000 | 0.58 | 0.58 | 1.01x |
| match | 1000000 | 3.53 | 1.54 | 2.29x |
| builtin_length | 1000000 | 0.05 | 0.28 | 0.16x |
| for_list | 1000000 | 0.45 | 0.36 | 1.24x |
