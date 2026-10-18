Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 3.59 | 3.28 | 1.09x |
| read_line | 200000 | 60.74 | 62.11 | 0.98x |
| map_put_get_8k | 16000 | 33.20 | 35.14 | 0.94x |
| int_eq | 10000000 | 1.03 | 0.97 | 1.06x |
| generic_call | 1000000 | 0.05 | 0.28 | 0.18x |
| method_call | 1000000 | 0.04 | 0.29 | 0.15x |
| try | 1000000 | 0.58 | 0.57 | 1.01x |
| match | 1000000 | 3.49 | 1.54 | 2.27x |
| builtin_length | 1000000 | 0.05 | 0.28 | 0.16x |
| for_list | 1000000 | 0.46 | 0.36 | 1.28x |
