Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 3.41 | 2.77 | 1.23x |
| read_line | 200000 | 79.64 | 62.83 | 1.27x |
| map_put_get_8k | 16000 | 46.73 | 31.49 | 1.48x |
| int_eq | 10000000 | 1.01 | 0.99 | 1.01x |
| generic_call | 1000000 | 0.31 | 0.28 | 1.09x |
| method_call | 1000000 | 0.66 | 0.29 | 2.29x |
| try | 1000000 | 1.17 | 0.57 | 2.05x |
| match | 1000000 | 3.43 | 1.58 | 2.16x |
| builtin_length | 1000000 | 0.66 | 0.28 | 2.33x |
| for_list | 1000000 | 0.62 | 0.33 | 1.89x |
