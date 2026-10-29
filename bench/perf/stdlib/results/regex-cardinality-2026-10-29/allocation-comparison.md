Baseline 4be5d6d8c2defb9fc6eb75c8c43bd68a5314d192; cached-name-flag candidate source snapshot. Host System allocator; no timing.

Production-cfg Rust wrapper size/alignment: baseline 32/8 bytes; candidate 40/8 bytes. Size delta 8 bytes per compiled wrapper; excluded from per-call counters.

| Case | Alloc calls before → after | Realloc calls before → after | Requested bytes before → after | Peak live bytes before → after |
| --- | ---: | ---: | ---: | ---: |
| rows.whole.0 | 0 → 0 | 0 → 0 | 0 → 0 | 0 → 0 |
| rows.whole.1 | 5 → 4 | 0 → 0 | 207 → 119 | 207 → 119 |
| rows.whole.128 | 259 → 258 | 10 → 5 | 14064 → 11072 | 9104 → 9088 |
| rows.whole.2000 | 4003 → 4002 | 18 → 9 | 225696 → 175472 | 143936 → 142768 |
| rows.grouped.1 | 7 → 7 | 0 → 0 | 294 → 294 | 294 → 294 |
| rows.grouped.2000 | 8003 → 8003 | 18 → 18 | 335728 → 335728 | 253968 → 253968 |
| rows.whole.zero_width_empty | 4 → 3 | 0 → 0 | 200 → 112 | 200 → 112 |
| rows.whole.long | 5 → 4 | 0 → 0 | 65736 → 65648 | 65736 → 65648 |
| rows.whole.empty_matches | 8 → 7 | 0 → 0 | 250 → 210 | 250 → 210 |
| rows.whole.over_limit | 1 → 1 | 0 → 0 | 64 → 64 | 64 → 64 |
| rows.whole.miss | 0 → 0 | 0 → 0 | 0 → 0 | 0 → 0 |
| first.whole.empty_input | 1 → 0 | 0 → 0 | 16 → 0 | 16 → 0 |
| first.whole.zero_width_empty | 2 → 1 | 0 → 0 | 112 → 24 | 112 → 24 |
| first.whole.1 | 3 → 2 | 0 → 0 | 119 → 31 | 119 → 31 |
| first.whole.long | 3 → 2 | 0 → 0 | 65648 → 65560 | 65648 → 65560 |
| first.whole.miss | 1 → 0 | 0 → 0 | 16 → 0 | 16 → 0 |
| first.grouped.1 | 5 → 5 | 0 → 0 | 158 → 158 | 158 → 158 |
| named.whole.empty_input | 1 → 0 | 0 → 0 | 16 → 0 | 16 → 0 |
| named.whole.zero_width_empty | 1 → 0 | 0 → 0 | 16 → 0 | 16 → 0 |
| named.unnamed_grouped.1 | 1 → 0 | 0 → 0 | 48 → 0 | 48 → 0 |
| named.whole.1 | 1 → 0 | 0 → 0 | 16 → 0 | 16 → 0 |
| named.whole.long | 1 → 0 | 0 → 0 | 16 → 0 | 16 → 0 |
| named.whole.miss | 1 → 0 | 0 → 0 | 16 → 0 | 16 → 0 |
| named.grouped.1 | 4 → 4 | 0 → 0 | 248 → 248 | 248 → 248 |
