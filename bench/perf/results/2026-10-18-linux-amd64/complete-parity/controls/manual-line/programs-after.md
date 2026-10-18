Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 3.66 | 2.77 | 1.32x |
| read_line | 200000 | 57.40 | 62.83 | 0.91x |
| map_put_get_8k | 16000 | 32.41 | 31.49 | 1.03x |
| int_eq | 10000000 | 1.03 | 0.99 | 1.04x |
| generic_call | 1000000 | 0.65 | 0.28 | 2.27x |
| method_call | 1000000 | 0.33 | 0.29 | 1.14x |
| try | 1000000 | 0.81 | 0.57 | 1.42x |
| match | 1000000 | 3.56 | 1.58 | 2.25x |
| builtin_length | 1000000 | 0.35 | 0.28 | 1.23x |
| for_list | 1000000 | 0.45 | 0.33 | 1.36x |
