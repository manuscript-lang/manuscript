Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 3.39 | 3.02 | 1.12x |
| read_line | 200000 | 56.70 | 62.76 | 0.90x |
| map_put_get_8k | 16000 | 32.34 | 32.15 | 1.01x |
| int_eq | 10000000 | 1.04 | 0.97 | 1.07x |
| generic_call | 1000000 | 0.05 | 0.28 | 0.18x |
| method_call | 1000000 | 0.04 | 0.28 | 0.16x |
| try | 1000000 | 0.60 | 0.56 | 1.08x |
| match | 1000000 | 2.02 | 1.52 | 1.33x |
| builtin_length | 1000000 | 0.05 | 0.28 | 0.17x |
| for_list | 1000000 | 0.37 | 0.39 | 0.95x |
