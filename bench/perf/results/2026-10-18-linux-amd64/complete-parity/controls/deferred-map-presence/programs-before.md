Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 3.95 | 2.73 | 1.45x |
| read_line | 200000 | 85.37 | 64.82 | 1.32x |
| map_put_get_8k | 16000 | 50.86 | 32.43 | 1.57x |
| int_eq | 10000000 | 1.06 | 0.99 | 1.07x |
| generic_call | 1000000 | 0.66 | 0.28 | 2.39x |
| method_call | 1000000 | 0.88 | 0.30 | 2.97x |
| try | 1000000 | 1.23 | 0.59 | 2.09x |
| match | 1000000 | 3.60 | 1.63 | 2.21x |
| builtin_length | 1000000 | 0.33 | 0.28 | 1.20x |
| for_list | 1000000 | 0.68 | 0.35 | 1.92x |
