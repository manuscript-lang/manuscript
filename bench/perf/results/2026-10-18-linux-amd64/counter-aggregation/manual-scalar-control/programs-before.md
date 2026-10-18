Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 3.74 | 2.92 | 1.28x |
| read_line | 200000 | 58.06 | 64.82 | 0.90x |
| map_put_get_8k | 16000 | 33.30 | 33.89 | 0.98x |
| int_eq | 10000000 | 1.02 | 1.00 | 1.02x |
| generic_call | 1000000 | 0.32 | 0.28 | 1.12x |
| method_call | 1000000 | 0.64 | 0.29 | 2.23x |
| try | 1000000 | 0.60 | 0.57 | 1.06x |
| match | 1000000 | 3.41 | 1.52 | 2.24x |
| builtin_length | 1000000 | 0.33 | 0.28 | 1.15x |
| for_list | 1000000 | 0.45 | 0.37 | 1.20x |
