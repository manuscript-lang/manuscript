Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 3.72 | 3.63 | 1.03x |
| read_line | 200000 | 87.28 | 68.56 | 1.27x |
| map_put_get_8k | 16000 | 51.56 | 34.34 | 1.50x |
| int_eq | 10000000 | 1.04 | 1.06 | 0.98x |
| generic_call | 1000000 | 0.64 | 0.28 | 2.28x |
| method_call | 1000000 | 1.01 | 0.30 | 3.37x |
| try | 1000000 | 1.22 | 0.59 | 2.08x |
| match | 1000000 | 3.73 | 1.73 | 2.15x |
| builtin_length | 1000000 | 0.34 | 0.29 | 1.16x |
| for_list | 1000000 | 0.66 | 0.40 | 1.64x |
