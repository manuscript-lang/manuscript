Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 3.58 | 3.18 | 1.12x |
| read_line | 200000 | 61.17 | 64.93 | 0.94x |
| map_put_get_8k | 16000 | 33.77 | 34.16 | 0.99x |
| int_eq | 10000000 | 1.03 | 0.99 | 1.04x |
| generic_call | 1000000 | 0.05 | 0.29 | 0.18x |
| method_call | 1000000 | 0.04 | 0.29 | 0.15x |
| try | 1000000 | 0.60 | 0.61 | 0.98x |
| match | 1000000 | 3.71 | 1.57 | 2.37x |
| builtin_length | 1000000 | 0.05 | 0.29 | 0.16x |
| for_list | 1000000 | 0.45 | 0.38 | 1.19x |
