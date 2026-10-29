Median of 7 alternating runs of 3 samples; all 16 cases and operation counts verified.

| operation | ops | before ns/op | after ns/op | after/before |
|---|---:|---:|---:|---:|
| regex.cardinality.whole.0 | 1 | 32.9 | 34.11 | 1.037x |
| regex.cardinality.whole.1 | 1 | 402.5 | 240.2 | 0.597x |
| regex.cardinality.whole.128 | 1 | 4.097e+04 | 2.456e+04 | 0.600x |
| regex.cardinality.whole.2000 | 1 | 6.112e+05 | 3.522e+05 | 0.576x |
| regex.cardinality.grouped.1 | 1 | 602.5 | 571.1 | 0.948x |
| regex.cardinality.grouped.2000 | 1 | 8.878e+05 | 8.466e+05 | 0.954x |
| regex.cardinality.whole.long | 1 | 7.782e+05 | 3.925e+05 | 0.504x |
| regex.cardinality.whole.empty_matches | 1 | 779.6 | 544.8 | 0.699x |
| regex.cardinality.whole.over_limit | 1 | 283.2 | 245.2 | 0.866x |
| regex.cardinality.first.whole.hit | 1 | 275.9 | 190 | 0.689x |
| regex.cardinality.first.whole.miss | 1 | 52 | 29.62 | 0.570x |
| regex.cardinality.first.grouped.hit | 1 | 387.5 | 381.7 | 0.985x |
| regex.cardinality.first.whole.long | 1 | 3.947e+05 | 3.988e+05 | 1.010x |
| regex.cardinality.named.whole.hit | 1 | 213.6 | 40.89 | 0.191x |
| regex.cardinality.named.whole.long_miss | 1 | 1.711e+05 | 36.65 | 0.000x |
| regex.cardinality.named.named.hit | 1 | 417.9 | 414.7 | 0.992x |
