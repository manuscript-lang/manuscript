Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 3.39 | 3.00 | 1.13x |
| read_line | 200000 | 86.68 | 70.01 | 1.24x |
| map_put_get_8k | 16000 | 66.73 | 32.82 | 2.03x |
| int_eq | 10000000 | 1.12 | 1.03 | 1.08x |
| generic_call | 1000000 | 0.92 | 0.28 | 3.33x |
| method_call | 1000000 | 2.64 | 0.29 | 9.04x |
| try | 1000000 | 2.78 | 0.57 | 4.89x |
| match | 1000000 | 4.39 | 1.59 | 2.76x |
| builtin_length | 1000000 | 0.92 | 0.27 | 3.39x |
| for_list | 1000000 | 0.96 | 0.39 | 2.47x |
