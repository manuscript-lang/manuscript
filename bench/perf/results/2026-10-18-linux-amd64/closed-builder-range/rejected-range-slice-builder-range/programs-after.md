Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 1.97 | 2.88 | 0.68x |
| read_line | 200000 | 56.07 | 60.43 | 0.93x |
| map_put_get_8k | 16000 | 32.55 | 30.76 | 1.06x |
| int_eq | 10000000 | 1.00 | 0.96 | 1.05x |
| generic_call | 1000000 | 0.05 | 0.28 | 0.18x |
| method_call | 1000000 | 0.04 | 0.27 | 0.16x |
| try | 1000000 | 0.60 | 0.56 | 1.07x |
| match | 1000000 | 3.35 | 1.55 | 2.16x |
| builtin_length | 1000000 | 0.05 | 0.28 | 0.16x |
| for_list | 1000000 | 0.39 | 0.39 | 1.00x |
