Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 4.02 | 3.51 | 1.15x |
| read_line | 200000 | 64.34 | 68.72 | 0.94x |
| map_put_get_8k | 16000 | 37.66 | 33.41 | 1.13x |
| int_eq | 10000000 | 1.05 | 1.07 | 0.99x |
| generic_call | 1000000 | 0.68 | 0.29 | 2.35x |
| method_call | 1000000 | 0.35 | 0.29 | 1.19x |
| try | 1000000 | 0.89 | 0.59 | 1.51x |
| match | 1000000 | 3.70 | 1.68 | 2.21x |
| builtin_length | 1000000 | 0.33 | 0.30 | 1.10x |
| for_list | 1000000 | 0.49 | 0.35 | 1.39x |
