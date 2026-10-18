Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 3.38 | 2.95 | 1.14x |
| read_line | 200000 | 57.60 | 65.82 | 0.88x |
| map_put_get_8k | 16000 | 32.80 | 33.18 | 0.99x |
| int_eq | 10000000 | 1.03 | 0.97 | 1.07x |
| generic_call | 1000000 | 0.64 | 0.28 | 2.28x |
| method_call | 1000000 | 0.34 | 0.28 | 1.23x |
| try | 1000000 | 0.83 | 0.57 | 1.45x |
| match | 1000000 | 3.59 | 1.58 | 2.28x |
| builtin_length | 1000000 | 0.33 | 0.28 | 1.17x |
| for_list | 1000000 | 0.45 | 0.34 | 1.35x |
