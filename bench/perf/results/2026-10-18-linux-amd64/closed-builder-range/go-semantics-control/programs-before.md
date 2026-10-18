Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 2.69 | 2.88 | 0.93x |
| read_line | 200000 | 62.79 | 61.76 | 1.02x |
| map_put_get_8k | 16000 | 32.38 | 31.99 | 1.01x |
| int_eq | 10000000 | 0.94 | 0.97 | 0.98x |
| generic_call | 1000000 | 0.28 | 0.28 | 1.00x |
| method_call | 1000000 | 0.29 | 0.28 | 1.03x |
| try | 1000000 | 0.56 | 0.57 | 0.97x |
| match | 1000000 | 3.18 | 1.57 | 2.02x |
| builtin_length | 1000000 | 0.28 | 0.28 | 1.01x |
| for_list | 1000000 | 0.35 | 0.39 | 0.90x |
