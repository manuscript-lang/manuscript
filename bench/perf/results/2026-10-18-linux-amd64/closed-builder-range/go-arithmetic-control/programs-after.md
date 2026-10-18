Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 2.67 | 2.80 | 0.95x |
| read_line | 200000 | 65.46 | 61.93 | 1.06x |
| map_put_get_8k | 16000 | 32.25 | 31.59 | 1.02x |
| int_eq | 10000000 | 0.94 | 0.95 | 0.99x |
| generic_call | 1000000 | 0.28 | 0.27 | 1.04x |
| method_call | 1000000 | 0.28 | 0.29 | 0.98x |
| try | 1000000 | 0.55 | 0.55 | 1.00x |
| match | 1000000 | 3.15 | 1.55 | 2.03x |
| builtin_length | 1000000 | 0.27 | 0.27 | 1.00x |
| for_list | 1000000 | 0.40 | 0.36 | 1.10x |
