Median of 30 alternating runs; ns/op. Checksums and operation counts verified.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 3.60 | 2.83 | 1.27x |
| read_line | 200000 | 81.59 | 64.05 | 1.27x |
| map_put_get_8k | 16000 | 66.97 | 31.90 | 2.10x |
| int_eq | 10000000 | 1.05 | 0.97 | 1.08x |
| generic_call | 1000000 | 0.87 | 0.28 | 3.07x |
| method_call | 1000000 | 2.59 | 0.27 | 9.44x |
| try | 1000000 | 2.61 | 0.58 | 4.51x |
| match | 1000000 | 4.23 | 1.57 | 2.69x |
| builtin_length | 1000000 | 0.88 | 0.28 | 3.10x |
| for_list | 1000000 | 0.90 | 0.38 | 2.37x |
