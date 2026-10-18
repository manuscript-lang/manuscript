Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 3.71 | 3.08 | 1.20x |
| read_line | 200000 | 61.59 | 66.38 | 0.93x |
| map_put_get_8k | 16000 | 34.67 | 34.22 | 1.01x |
| int_eq | 10000000 | 1.09 | 1.05 | 1.04x |
| generic_call | 1000000 | 0.05 | 0.28 | 0.18x |
| method_call | 1000000 | 0.04 | 0.28 | 0.15x |
| try | 1000000 | 0.65 | 0.58 | 1.12x |
| match | 1000000 | 3.61 | 1.59 | 2.27x |
| builtin_length | 1000000 | 0.05 | 0.28 | 0.16x |
| for_list | 1000000 | 0.46 | 0.38 | 1.20x |
