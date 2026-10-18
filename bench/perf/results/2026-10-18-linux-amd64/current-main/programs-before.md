Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 6.42 | 2.83 | 2.27x |
| read_line | 200000 | 80.17 | 64.05 | 1.25x |
| map_put_get_8k | 16000 | 64.52 | 31.90 | 2.02x |
| int_eq | 10000000 | 1.40 | 0.97 | 1.43x |
| generic_call | 1000000 | 0.89 | 0.28 | 3.14x |
| method_call | 1000000 | 2.33 | 0.27 | 8.49x |
| try | 1000000 | 3.51 | 0.58 | 6.07x |
| match | 1000000 | 5.72 | 1.57 | 3.64x |
| builtin_length | 1000000 | 0.87 | 0.28 | 3.09x |
| for_list | 1000000 | 0.89 | 0.38 | 2.33x |
