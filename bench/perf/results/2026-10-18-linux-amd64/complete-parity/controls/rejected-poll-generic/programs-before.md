Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 4.37 | 3.35 | 1.30x |
| read_line | 200000 | 67.86 | 74.16 | 0.92x |
| map_put_get_8k | 16000 | 35.63 | 36.86 | 0.97x |
| int_eq | 10000000 | 1.06 | 1.12 | 0.94x |
| generic_call | 1000000 | 0.67 | 0.30 | 2.26x |
| method_call | 1000000 | 0.34 | 0.34 | 0.99x |
| try | 1000000 | 0.86 | 0.63 | 1.37x |
| match | 1000000 | 3.65 | 1.79 | 2.04x |
| builtin_length | 1000000 | 0.34 | 0.29 | 1.17x |
| for_list | 1000000 | 0.48 | 0.35 | 1.36x |
