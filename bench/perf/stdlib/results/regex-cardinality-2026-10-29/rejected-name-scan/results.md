Median of 7 alternating runs of 3 samples; all 7 cases and operation counts verified.

| operation | ops | before ns/op | after ns/op | after/before |
|---|---:|---:|---:|---:|
| regex.cardinality.named.whole.hit | 1 | 47.26 | 38.8 | 0.821x |
| regex.cardinality.named.whole.long_miss | 1 | 48.38 | 42.49 | 0.878x |
| regex.cardinality.named.named.hit | 1 | 452.7 | 402.2 | 0.888x |
| regex.cardinality.named.anonymous.hit | 1 | 310.7 | 49.07 | 0.158x |
| regex.cardinality.named.anonymous.long_miss | 1 | 1.636e+05 | 50 | 0.000x |
| regex.cardinality.named.late.hit | 1 | 2698 | 2543 | 0.942x |
| regex.cardinality.named.late.miss | 1 | 159.9 | 218.1 | 1.364x |
