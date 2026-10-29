Seven process medians per variant, each from 3 timed samples. CV uses the population standard deviation of process medians. Ranges are process-median ranges, not individual-sample bounds. The paired-ratio median is diagnostic; results.md retains the canonical ratio of medians.

| case | before min–max ns | after min–max ns | before CV | after CV | paired-ratio median |
| --- | ---: | ---: | ---: | ---: | ---: |
| regex.cardinality.whole.0 | 34.0495–41.1261 | 34.1575–48.9479 | 7.10% | 12.50% | 1.022x |
| regex.cardinality.whole.1 | 413.229–538.03 | 250.117–546.815 | 9.69% | 33.19% | 0.6128x |
| regex.cardinality.whole.128 | 41849–54605.6 | 22703.5–36864 | 9.66% | 16.71% | 0.5453x |
| regex.cardinality.whole.2000 | 600204–758908 | 356727–549265 | 8.11% | 15.90% | 0.5887x |
| regex.cardinality.grouped.1 | 567.765–606.113 | 585.506–1321.62 | 2.56% | 33.11% | 1.869x |
| regex.cardinality.grouped.2000 | 867069–1.28346e+06 | 967514–1.46481e+06 | 12.58% | 14.33% | 1.06x |
| regex.cardinality.whole.long | 810378–1.14828e+06 | 401441–895989 | 11.96% | 31.97% | 0.5225x |
| regex.cardinality.whole.empty_matches | 784.132–1592.96 | 548.932–1166.47 | 26.01% | 27.36% | 0.659x |
| regex.cardinality.whole.over_limit | 250.02–328.135 | 257.06–665.892 | 9.60% | 34.07% | 1.375x |
| regex.cardinality.first.whole.hit | 248.61–432.928 | 180.225–415.892 | 21.24% | 36.59% | 0.8036x |
| regex.cardinality.first.whole.miss | 52.792–60.0284 | 28.9931–70.5214 | 4.69% | 34.01% | 0.7357x |
| regex.cardinality.first.grouped.hit | 383.184–462.816 | 370.067–1290.65 | 7.41% | 52.35% | 0.9394x |
| regex.cardinality.first.whole.long | 403436–925113 | 390462–1.68859e+06 | 35.31% | 61.52% | 1.023x |
| regex.cardinality.named.whole.hit | 209.956–414.505 | 32.1434–115.465 | 27.30% | 60.32% | 0.1612x |
| regex.cardinality.named.whole.long_miss | 150329–242654 | 32.647–80.403 | 16.66% | 38.02% | 0.0002661x |
| regex.cardinality.named.named.hit | 375.192–872.053 | 402.49–2181.67 | 32.45% | 85.14% | 1.073x |
| regex.cardinality.named.anonymous.hit | 246.536–467.343 | 33.3564–175.692 | 23.23% | 78.74% | 0.1353x |
| regex.cardinality.named.anonymous.long_miss | 147482–334214 | 32.877–129.311 | 31.93% | 61.65% | 0.0002379x |
| regex.cardinality.named.late.hit | 2737.62–4933.07 | 2644.74–20581.3 | 22.24% | 104.20% | 1.026x |
| regex.cardinality.named.late.miss | 147.797–222.475 | 142.726–323.704 | 14.46% | 32.48% | 0.9867x |
