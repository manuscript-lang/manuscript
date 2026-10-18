Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 3.43 | 2.73 | 1.26x |
| read_line | 200000 | 80.64 | 64.82 | 1.24x |
| map_put_get_8k | 16000 | 47.79 | 32.43 | 1.47x |
| int_eq | 10000000 | 0.97 | 0.99 | 0.98x |
| generic_call | 1000000 | 0.32 | 0.28 | 1.15x |
| method_call | 1000000 | 0.88 | 0.30 | 2.97x |
| try | 1000000 | 0.79 | 0.59 | 1.33x |
| match | 1000000 | 3.43 | 1.63 | 2.10x |
| builtin_length | 1000000 | 0.61 | 0.28 | 2.21x |
| for_list | 1000000 | 0.45 | 0.35 | 1.27x |
