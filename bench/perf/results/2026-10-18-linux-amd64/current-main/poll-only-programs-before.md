Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 4.05 | 3.00 | 1.35x |
| read_line | 200000 | 84.37 | 70.01 | 1.21x |
| map_put_get_8k | 16000 | 71.40 | 32.82 | 2.18x |
| int_eq | 10000000 | 1.11 | 1.03 | 1.08x |
| generic_call | 1000000 | 0.93 | 0.28 | 3.38x |
| method_call | 1000000 | 2.64 | 0.29 | 9.03x |
| try | 1000000 | 2.77 | 0.57 | 4.88x |
| match | 1000000 | 4.45 | 1.59 | 2.80x |
| builtin_length | 1000000 | 0.90 | 0.27 | 3.34x |
| for_list | 1000000 | 0.94 | 0.39 | 2.42x |
