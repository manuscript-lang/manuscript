Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 3.94 | 2.93 | 1.34x |
| read_line | 200000 | 87.39 | 67.24 | 1.30x |
| map_put_get_8k | 16000 | 67.01 | 34.01 | 1.97x |
| int_eq | 10000000 | 1.11 | 1.01 | 1.10x |
| generic_call | 1000000 | 0.89 | 0.27 | 3.30x |
| method_call | 1000000 | 2.71 | 0.29 | 9.49x |
| try | 1000000 | 2.75 | 0.56 | 4.94x |
| match | 1000000 | 4.33 | 1.59 | 2.73x |
| builtin_length | 1000000 | 0.87 | 0.28 | 3.06x |
| for_list | 1000000 | 0.94 | 0.40 | 2.38x |
