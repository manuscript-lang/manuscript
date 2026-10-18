Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 3.34 | 2.83 | 1.18x |
| read_line | 200000 | 57.63 | 62.90 | 0.92x |
| map_put_get_8k | 16000 | 32.60 | 31.71 | 1.03x |
| int_eq | 10000000 | 1.03 | 0.97 | 1.06x |
| generic_call | 1000000 | 0.32 | 0.28 | 1.15x |
| method_call | 1000000 | 0.33 | 0.28 | 1.18x |
| try | 1000000 | 1.15 | 0.57 | 2.02x |
| match | 1000000 | 3.45 | 1.54 | 2.24x |
| builtin_length | 1000000 | 0.67 | 0.28 | 2.37x |
| for_list | 1000000 | 0.64 | 0.39 | 1.65x |
