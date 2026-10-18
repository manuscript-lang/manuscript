Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 3.57 | 3.51 | 1.02x |
| read_line | 200000 | 63.37 | 68.72 | 0.92x |
| map_put_get_8k | 16000 | 35.62 | 33.41 | 1.07x |
| int_eq | 10000000 | 1.04 | 1.07 | 0.97x |
| generic_call | 1000000 | 0.36 | 0.29 | 1.24x |
| method_call | 1000000 | 0.69 | 0.29 | 2.38x |
| try | 1000000 | 0.85 | 0.59 | 1.46x |
| match | 1000000 | 3.91 | 1.68 | 2.33x |
| builtin_length | 1000000 | 0.39 | 0.30 | 1.30x |
| for_list | 1000000 | 0.49 | 0.35 | 1.39x |
