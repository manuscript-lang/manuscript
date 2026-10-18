Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 2.03 | 2.80 | 0.73x |
| read_line | 200000 | 58.37 | 63.82 | 0.91x |
| map_put_get_8k | 16000 | 33.53 | 31.78 | 1.05x |
| int_eq | 10000000 | 1.01 | 0.96 | 1.05x |
| generic_call | 1000000 | 0.05 | 0.27 | 0.19x |
| method_call | 1000000 | 0.04 | 0.28 | 0.15x |
| try | 1000000 | 0.65 | 0.59 | 1.09x |
| match | 1000000 | 3.43 | 1.54 | 2.22x |
| builtin_length | 1000000 | 0.05 | 0.28 | 0.16x |
| for_list | 1000000 | 0.38 | 0.33 | 1.15x |
