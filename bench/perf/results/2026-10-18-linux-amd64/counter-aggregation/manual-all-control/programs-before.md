Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 3.74 | 3.18 | 1.17x |
| read_line | 200000 | 61.18 | 64.93 | 0.94x |
| map_put_get_8k | 16000 | 34.33 | 34.16 | 1.00x |
| int_eq | 10000000 | 1.02 | 0.99 | 1.03x |
| generic_call | 1000000 | 0.31 | 0.29 | 1.08x |
| method_call | 1000000 | 0.63 | 0.29 | 2.20x |
| try | 1000000 | 0.65 | 0.61 | 1.06x |
| match | 1000000 | 3.60 | 1.57 | 2.30x |
| builtin_length | 1000000 | 0.33 | 0.29 | 1.15x |
| for_list | 1000000 | 0.50 | 0.38 | 1.31x |
