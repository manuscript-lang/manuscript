Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 3.32 | 3.18 | 1.04x |
| read_line | 200000 | 80.66 | 61.78 | 1.31x |
| map_put_get_8k | 16000 | 64.68 | 32.05 | 2.02x |
| int_eq | 10000000 | 1.37 | 0.96 | 1.42x |
| generic_call | 1000000 | 0.64 | 0.28 | 2.33x |
| method_call | 1000000 | 1.13 | 0.28 | 4.01x |
| try | 1000000 | 1.73 | 0.56 | 3.09x |
| match | 1000000 | 4.13 | 1.54 | 2.68x |
| builtin_length | 1000000 | 0.87 | 0.27 | 3.22x |
| for_list | 1000000 | 0.95 | 0.37 | 2.56x |
