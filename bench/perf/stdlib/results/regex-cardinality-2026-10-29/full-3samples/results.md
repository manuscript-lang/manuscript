Median of 7 alternating runs of 3 samples; all 20 cases and operation counts verified.

| operation | ops | before ns/op | after ns/op | after/before |
|---|---:|---:|---:|---:|
| regex.cardinality.whole.0 | 1 | 35.85 | 35.64 | 0.994x |
| regex.cardinality.whole.1 | 1 | 447 | 267.9 | 0.599x |
| regex.cardinality.whole.128 | 1 | 4.35e+04 | 2.513e+04 | 0.578x |
| regex.cardinality.whole.2000 | 1 | 6.237e+05 | 3.784e+05 | 0.607x |
| regex.cardinality.grouped.1 | 1 | 596 | 1064 | 1.785x |
| regex.cardinality.grouped.2000 | 1 | 9.472e+05 | 1.091e+06 | 1.152x |
| regex.cardinality.whole.long | 1 | 8.668e+05 | 4.941e+05 | 0.570x |
| regex.cardinality.whole.empty_matches | 1 | 860.1 | 775.5 | 0.902x |
| regex.cardinality.whole.over_limit | 1 | 264.2 | 343.8 | 1.301x |
| regex.cardinality.first.whole.hit | 1 | 257.7 | 213.2 | 0.827x |
| regex.cardinality.first.whole.miss | 1 | 55.31 | 39.18 | 0.708x |
| regex.cardinality.first.grouped.hit | 1 | 414.3 | 420.1 | 1.014x |
| regex.cardinality.first.whole.long | 1 | 4.231e+05 | 4.971e+05 | 1.175x |
| regex.cardinality.named.whole.hit | 1 | 221.1 | 35.08 | 0.159x |
| regex.cardinality.named.whole.long_miss | 1 | 1.637e+05 | 40 | 0.000x |
| regex.cardinality.named.named.hit | 1 | 428.3 | 467.2 | 1.091x |
| regex.cardinality.named.anonymous.hit | 1 | 269.2 | 39.07 | 0.145x |
| regex.cardinality.named.anonymous.long_miss | 1 | 1.697e+05 | 38.11 | 0.000x |
| regex.cardinality.named.late.hit | 1 | 3003 | 3081 | 1.026x |
| regex.cardinality.named.late.miss | 1 | 158 | 173.4 | 1.097x |
