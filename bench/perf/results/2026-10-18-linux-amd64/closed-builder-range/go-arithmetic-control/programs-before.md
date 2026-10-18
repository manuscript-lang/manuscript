Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 2.64 | 2.80 | 0.94x |
| read_line | 200000 | 63.55 | 61.93 | 1.03x |
| map_put_get_8k | 16000 | 32.51 | 31.59 | 1.03x |
| int_eq | 10000000 | 0.95 | 0.95 | 1.00x |
| generic_call | 1000000 | 0.57 | 0.27 | 2.09x |
| method_call | 1000000 | 0.28 | 0.29 | 0.97x |
| try | 1000000 | 0.56 | 0.55 | 1.01x |
| match | 1000000 | 3.23 | 1.55 | 2.08x |
| builtin_length | 1000000 | 0.55 | 0.27 | 2.05x |
| for_list | 1000000 | 0.40 | 0.36 | 1.11x |
