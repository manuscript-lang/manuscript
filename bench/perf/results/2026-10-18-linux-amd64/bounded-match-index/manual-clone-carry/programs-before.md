Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 2.23 | 2.93 | 0.76x |
| read_line | 200000 | 59.33 | 64.17 | 0.92x |
| map_put_get_8k | 16000 | 33.52 | 31.27 | 1.07x |
| int_eq | 10000000 | 1.02 | 0.97 | 1.06x |
| generic_call | 1000000 | 0.05 | 0.28 | 0.18x |
| method_call | 1000000 | 0.04 | 0.28 | 0.15x |
| try | 1000000 | 0.63 | 0.57 | 1.10x |
| match | 1000000 | 3.41 | 1.55 | 2.20x |
| builtin_length | 1000000 | 0.05 | 0.28 | 0.17x |
| for_list | 1000000 | 0.36 | 0.34 | 1.05x |
