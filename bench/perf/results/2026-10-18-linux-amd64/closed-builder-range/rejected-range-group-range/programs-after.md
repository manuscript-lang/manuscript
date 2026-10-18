Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 4.23 | 3.51 | 1.21x |
| read_line | 200000 | 63.67 | 67.75 | 0.94x |
| map_put_get_8k | 16000 | 35.34 | 33.92 | 1.04x |
| int_eq | 10000000 | 1.04 | 1.01 | 1.03x |
| generic_call | 1000000 | 0.05 | 0.28 | 0.18x |
| method_call | 1000000 | 0.04 | 0.29 | 0.15x |
| try | 1000000 | 0.60 | 0.58 | 1.03x |
| match | 1000000 | 3.56 | 1.58 | 2.25x |
| builtin_length | 1000000 | 0.05 | 0.28 | 0.17x |
| for_list | 1000000 | 0.64 | 0.38 | 1.67x |
