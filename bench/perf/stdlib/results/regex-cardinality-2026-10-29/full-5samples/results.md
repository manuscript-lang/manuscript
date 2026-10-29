Median of 7 alternating runs of 5 samples; all 20 cases and operation counts verified.

| operation | ops | before ns/op | after ns/op | after/before |
|---|---:|---:|---:|---:|
| regex.cardinality.whole.0 | 1 | 36.58 | 47.84 | 1.308x |
| regex.cardinality.whole.1 | 1 | 425 | 320 | 0.753x |
| regex.cardinality.whole.128 | 1 | 4.435e+04 | 2.835e+04 | 0.639x |
| regex.cardinality.whole.2000 | 1 | 6.564e+05 | 4.725e+05 | 0.720x |
| regex.cardinality.grouped.1 | 1 | 648.6 | 625.2 | 0.964x |
| regex.cardinality.grouped.2000 | 1 | 9.688e+05 | 9.853e+05 | 1.017x |
| regex.cardinality.whole.long | 1 | 8.243e+05 | 4.716e+05 | 0.572x |
| regex.cardinality.whole.empty_matches | 1 | 860.9 | 744.1 | 0.864x |
| regex.cardinality.whole.over_limit | 1 | 290.4 | 315.9 | 1.088x |
| regex.cardinality.first.whole.hit | 1 | 282.2 | 217.5 | 0.771x |
| regex.cardinality.first.whole.miss | 1 | 58.62 | 34.88 | 0.595x |
| regex.cardinality.first.grouped.hit | 1 | 413.6 | 446.5 | 1.080x |
| regex.cardinality.first.whole.long | 1 | 4.26e+05 | 4.671e+05 | 1.096x |
| regex.cardinality.named.whole.hit | 1 | 246.5 | 38.99 | 0.158x |
| regex.cardinality.named.whole.long_miss | 1 | 1.737e+05 | 38.87 | 0.000x |
| regex.cardinality.named.named.hit | 1 | 420.2 | 452.6 | 1.077x |
| regex.cardinality.named.anonymous.hit | 1 | 279.5 | 45.11 | 0.161x |
| regex.cardinality.named.anonymous.long_miss | 1 | 1.721e+05 | 43.48 | 0.000x |
| regex.cardinality.named.late.hit | 1 | 3297 | 3751 | 1.137x |
| regex.cardinality.named.late.miss | 1 | 179 | 153.7 | 0.859x |
