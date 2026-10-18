Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 3.38 | 2.88 | 1.17x |
| read_line | 200000 | 57.53 | 60.43 | 0.95x |
| map_put_get_8k | 16000 | 34.78 | 30.76 | 1.13x |
| int_eq | 10000000 | 1.03 | 0.96 | 1.08x |
| generic_call | 1000000 | 0.05 | 0.28 | 0.18x |
| method_call | 1000000 | 0.04 | 0.27 | 0.16x |
| try | 1000000 | 0.57 | 0.56 | 1.02x |
| match | 1000000 | 3.38 | 1.55 | 2.19x |
| builtin_length | 1000000 | 0.05 | 0.28 | 0.16x |
| for_list | 1000000 | 0.45 | 0.39 | 1.17x |
