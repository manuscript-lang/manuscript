Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 3.84 | 3.02 | 1.27x |
| read_line | 200000 | 59.40 | 62.76 | 0.95x |
| map_put_get_8k | 16000 | 32.67 | 32.15 | 1.02x |
| int_eq | 10000000 | 1.02 | 0.97 | 1.05x |
| generic_call | 1000000 | 0.05 | 0.28 | 0.18x |
| method_call | 1000000 | 0.04 | 0.28 | 0.16x |
| try | 1000000 | 0.57 | 0.56 | 1.03x |
| match | 1000000 | 3.47 | 1.52 | 2.29x |
| builtin_length | 1000000 | 0.05 | 0.28 | 0.17x |
| for_list | 1000000 | 0.49 | 0.39 | 1.23x |
