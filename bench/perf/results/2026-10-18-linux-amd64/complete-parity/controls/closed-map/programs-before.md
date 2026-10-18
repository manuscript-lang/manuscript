Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 3.35 | 3.58 | 0.93x |
| read_line | 200000 | 82.54 | 65.29 | 1.26x |
| map_put_get_8k | 16000 | 65.45 | 32.64 | 2.01x |
| int_eq | 10000000 | 1.06 | 0.98 | 1.08x |
| generic_call | 1000000 | 0.32 | 0.27 | 1.18x |
| method_call | 1000000 | 0.90 | 0.29 | 3.12x |
| try | 1000000 | 0.80 | 0.57 | 1.41x |
| match | 1000000 | 4.29 | 1.53 | 2.80x |
| builtin_length | 1000000 | 0.90 | 0.27 | 3.31x |
| for_list | 1000000 | 0.96 | 0.35 | 2.72x |
