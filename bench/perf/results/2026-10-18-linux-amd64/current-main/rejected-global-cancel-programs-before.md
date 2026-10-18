Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 3.59 | 2.94 | 1.22x |
| read_line | 200000 | 84.01 | 66.30 | 1.27x |
| map_put_get_8k | 16000 | 62.00 | 31.30 | 1.98x |
| int_eq | 10000000 | 1.06 | 0.98 | 1.08x |
| generic_call | 1000000 | 0.91 | 0.27 | 3.33x |
| method_call | 1000000 | 2.58 | 0.29 | 8.81x |
| try | 1000000 | 2.66 | 0.56 | 4.76x |
| match | 1000000 | 4.30 | 1.58 | 2.72x |
| builtin_length | 1000000 | 0.88 | 0.30 | 2.94x |
| for_list | 1000000 | 0.89 | 0.34 | 2.59x |
