Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 3.38 | 3.09 | 1.09x |
| read_line | 200000 | 58.06 | 62.08 | 0.94x |
| map_put_get_8k | 16000 | 33.03 | 32.30 | 1.02x |
| int_eq | 10000000 | 1.02 | 0.98 | 1.05x |
| generic_call | 1000000 | 0.06 | 0.27 | 0.23x |
| method_call | 1000000 | 0.05 | 0.29 | 0.19x |
| try | 1000000 | 0.57 | 0.57 | 1.00x |
| match | 1000000 | 2.03 | 1.56 | 1.30x |
| builtin_length | 1000000 | 0.06 | 0.28 | 0.20x |
| for_list | 1000000 | 0.64 | 0.39 | 1.64x |
