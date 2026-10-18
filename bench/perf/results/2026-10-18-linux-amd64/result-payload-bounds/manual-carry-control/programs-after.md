Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 4.11 | 2.87 | 1.43x |
| read_line | 200000 | 64.33 | 69.54 | 0.93x |
| map_put_get_8k | 16000 | 35.35 | 34.71 | 1.02x |
| int_eq | 10000000 | 1.03 | 1.01 | 1.02x |
| generic_call | 1000000 | 0.65 | 0.29 | 2.20x |
| method_call | 1000000 | 0.35 | 0.28 | 1.26x |
| try | 1000000 | 0.60 | 0.59 | 1.02x |
| match | 1000000 | 3.72 | 1.56 | 2.39x |
| builtin_length | 1000000 | 0.62 | 0.29 | 2.14x |
| for_list | 1000000 | 0.62 | 0.40 | 1.56x |
