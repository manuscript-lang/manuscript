Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 2.05 | 3.13 | 0.66x |
| read_line | 200000 | 61.40 | 63.02 | 0.97x |
| map_put_get_8k | 16000 | 35.42 | 31.58 | 1.12x |
| int_eq | 10000000 | 1.05 | 0.98 | 1.07x |
| generic_call | 1000000 | 0.05 | 0.27 | 0.19x |
| method_call | 1000000 | 0.04 | 0.29 | 0.15x |
| try | 1000000 | 0.65 | 0.57 | 1.14x |
| match | 1000000 | 3.43 | 1.55 | 2.21x |
| builtin_length | 1000000 | 0.05 | 0.28 | 0.17x |
| for_list | 1000000 | 0.38 | 0.39 | 0.98x |
