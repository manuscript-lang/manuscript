Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 3.41 | 2.88 | 1.18x |
| read_line | 200000 | 56.05 | 61.76 | 0.91x |
| map_put_get_8k | 16000 | 33.65 | 31.99 | 1.05x |
| int_eq | 10000000 | 1.03 | 0.97 | 1.07x |
| generic_call | 1000000 | 0.05 | 0.28 | 0.18x |
| method_call | 1000000 | 0.04 | 0.28 | 0.15x |
| try | 1000000 | 0.60 | 0.57 | 1.04x |
| match | 1000000 | 3.44 | 1.57 | 2.19x |
| builtin_length | 1000000 | 0.05 | 0.28 | 0.17x |
| for_list | 1000000 | 0.44 | 0.39 | 1.12x |
