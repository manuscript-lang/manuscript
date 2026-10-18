Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 3.53 | 2.93 | 1.20x |
| read_line | 200000 | 56.38 | 63.16 | 0.89x |
| map_put_get_8k | 16000 | 33.32 | 33.50 | 0.99x |
| int_eq | 10000000 | 1.03 | 0.96 | 1.07x |
| generic_call | 1000000 | 0.06 | 0.27 | 0.23x |
| method_call | 1000000 | 0.05 | 0.29 | 0.19x |
| try | 1000000 | 0.58 | 0.57 | 1.01x |
| match | 1000000 | 3.49 | 1.56 | 2.25x |
| builtin_length | 1000000 | 0.06 | 0.29 | 0.20x |
| for_list | 1000000 | 0.48 | 0.40 | 1.21x |
