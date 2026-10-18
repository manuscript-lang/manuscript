Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 2.00 | 2.93 | 0.68x |
| read_line | 200000 | 58.70 | 64.70 | 0.91x |
| map_put_get_8k | 16000 | 34.76 | 31.95 | 1.09x |
| int_eq | 10000000 | 1.03 | 0.98 | 1.04x |
| generic_call | 1000000 | 0.05 | 0.28 | 0.18x |
| method_call | 1000000 | 0.04 | 0.29 | 0.15x |
| try | 1000000 | 0.63 | 0.56 | 1.11x |
| match | 1000000 | 2.28 | 1.53 | 1.49x |
| builtin_length | 1000000 | 0.05 | 0.28 | 0.17x |
| for_list | 1000000 | 0.36 | 0.36 | 1.01x |
