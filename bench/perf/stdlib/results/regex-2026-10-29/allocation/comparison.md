Baseline regex source: 7e2e62357 (byte-identical to historical 4c0a1cb8 snapshot). Exact final working-tree candidate; allocation counters only.

| Case | Alloc calls before → after | Realloc calls before → after | Requested bytes before → after | Peak live bytes before → after |
| --- | ---: | ---: | ---: | ---: |
| captures_all.0 | 0 → 0 | 0 → 0 | 0 → 0 | 0 → 0 |
| replace_template.0 | 0 → 0 | 0 → 0 | 0 → 0 | 0 → 0 |
| captures_all.1 | 7 → 7 | 0 → 0 | 318 → 294 | 270 → 294 |
| replace_template.1 | 3 → 2 | 2 → 1 | 99 → 72 | 73 → 64 |
| captures_all.128 | 642 → 515 | 10 → 10 | 30304 → 21136 | 19248 → 16176 |
| replace_template.128 | 257 → 129 | 136 → 8 | 13815 → 10232 | 2368 → 2096 |
| captures_all.2000 | 10002 → 8003 | 18 → 18 | 479680 → 335728 | 301968 → 253968 |
| replace_template.2000 | 4001 → 2001 | 2012 → 12 | 217719 → 161528 | 36928 → 32816 |
| replace_template.mixed_long_short.2000 | 4001 → 2001 | 3 → 2 | 931966 → 522752 | 393250 → 262176 |
| replace_template.literal.0 | 0 → 0 | 0 → 0 | 0 → 0 | 0 → 0 |
| replace_template.literal.1 | 3 → 1 | 0 → 0 | 64 → 8 | 64 → 8 |
| replace_template.literal.2000 | 4001 → 1 | 11 → 11 | 144760 → 32760 | 16440 → 16384 |
| replace_template.unused_large | 1 → 1 | 0 → 0 | 8 → 8 | 8 → 8 |
