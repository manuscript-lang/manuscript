Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 3.42 | 3.06 | 1.12x |
| read_line | 200000 | 80.08 | 64.52 | 1.24x |
| map_put_get_8k | 16000 | 64.10 | 31.70 | 2.02x |
| int_eq | 10000000 | 1.05 | 0.98 | 1.07x |
| generic_call | 1000000 | 0.87 | 0.28 | 3.09x |
| method_call | 1000000 | 2.57 | 0.29 | 8.90x |
| try | 1000000 | 2.66 | 0.57 | 4.70x |
| match | 1000000 | 4.35 | 1.55 | 2.80x |
| builtin_length | 1000000 | 0.88 | 0.27 | 3.24x |
| for_list | 1000000 | 0.92 | 0.37 | 2.48x |
