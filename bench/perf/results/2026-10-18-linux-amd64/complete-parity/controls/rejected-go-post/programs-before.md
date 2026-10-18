Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 3.25 | 2.69 | 1.21x |
| read_line | 200000 | 59.82 | 63.11 | 0.95x |
| map_put_get_8k | 16000 | 33.88 | 31.38 | 1.08x |
| int_eq | 10000000 | 1.04 | 0.97 | 1.08x |
| generic_call | 1000000 | 0.65 | 0.28 | 2.28x |
| method_call | 1000000 | 0.32 | 0.29 | 1.12x |
| try | 1000000 | 0.78 | 0.56 | 1.40x |
| match | 1000000 | 3.38 | 1.54 | 2.19x |
| builtin_length | 1000000 | 0.34 | 0.28 | 1.20x |
| for_list | 1000000 | 0.46 | 0.37 | 1.22x |
