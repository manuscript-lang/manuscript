# Manuscript vs hand-written Go (performance)

Part of the [performance benchmark](../README.md) (not the agent benchmark).

Main at 88a6360, 2026-10-17. Best of 7, ns/op. Run `MS=./ms sh bench/perf/programs/run.sh 7`.
Absolute numbers vary by machine and run; compare ratios on one machine.

| operation | ops | Manuscript | Go | ratio |
|---|---:|---:|---:|---:|
| string_append_50k | 50000 | 7.2 | 4.29 | 1.7x |
| read_line | 200000 | 149.5 | 101.38 | 1.5x |
| map_put_get_8k | 16000 | 67.3 | 34.61 | 1.9x |
| int_eq | 10000000 | 2.1 | 1.25 | 1.7x |
| generic_call | 1000000 | 1.3 | 1.73 | 0.8x |
| method_call | 1000000 | 2.6 | 2.18 | 1.2x |
| try | 1000000 | 4.0 | 3.71 | 1.1x |
| match | 1000000 | 7.1 | 3.04 | 2.3x |
| builtin_length | 1000000 | 1.3 | 0.38 | 3.3x |
| for_list | 1000000 | 1.7 | 1.09 | 1.5x |
