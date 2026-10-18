Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 2.29 | 3.23 | 0.71x |
| read_line | 200000 | 62.57 | 65.12 | 0.96x |
| map_put_get_8k | 16000 | 34.11 | 31.68 | 1.08x |
| int_eq | 10000000 | 1.00 | 1.00 | 1.00x |
| generic_call | 1000000 | 0.05 | 0.28 | 0.18x |
| method_call | 1000000 | 0.04 | 0.30 | 0.14x |
| try | 1000000 | 0.62 | 0.60 | 1.03x |
| match | 1000000 | 3.41 | 1.65 | 2.07x |
| builtin_length | 1000000 | 0.05 | 0.29 | 0.16x |
| for_list | 1000000 | 0.38 | 0.36 | 1.05x |
