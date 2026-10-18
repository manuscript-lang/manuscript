Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 3.23 | 2.95 | 1.09x |
| read_line | 200000 | 56.96 | 65.82 | 0.87x |
| map_put_get_8k | 16000 | 34.00 | 33.18 | 1.02x |
| int_eq | 10000000 | 0.99 | 0.97 | 1.02x |
| generic_call | 1000000 | 0.32 | 0.28 | 1.14x |
| method_call | 1000000 | 0.64 | 0.28 | 2.33x |
| try | 1000000 | 1.15 | 0.57 | 2.01x |
| match | 1000000 | 4.30 | 1.58 | 2.73x |
| builtin_length | 1000000 | 0.67 | 0.28 | 2.35x |
| for_list | 1000000 | 0.63 | 0.34 | 1.87x |
