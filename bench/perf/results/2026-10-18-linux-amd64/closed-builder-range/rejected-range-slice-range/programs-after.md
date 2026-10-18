Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 3.52 | 2.86 | 1.23x |
| read_line | 200000 | 56.33 | 63.95 | 0.88x |
| map_put_get_8k | 16000 | 32.08 | 32.25 | 0.99x |
| int_eq | 10000000 | 1.03 | 0.98 | 1.05x |
| generic_call | 1000000 | 0.05 | 0.28 | 0.18x |
| method_call | 1000000 | 0.04 | 0.28 | 0.16x |
| try | 1000000 | 0.58 | 0.56 | 1.05x |
| match | 1000000 | 3.47 | 1.53 | 2.27x |
| builtin_length | 1000000 | 0.05 | 0.28 | 0.16x |
| for_list | 1000000 | 0.67 | 0.37 | 1.82x |
