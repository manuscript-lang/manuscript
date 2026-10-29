Seven process medians per variant, each from 3 timed samples. CV uses the population standard deviation of process medians. Ranges are process-median ranges, not individual-sample bounds. The paired-ratio median is diagnostic; results.md retains the canonical ratio of medians.

| case | before min–max ns | after min–max ns | before CV | after CV | paired-ratio median |
| --- | ---: | ---: | ---: | ---: | ---: |
| regex.cardinality.named.whole.hit | 37.8962–72.5347 | 38.1666–61.9075 | 25.89% | 18.48% | 0.8535x |
| regex.cardinality.named.whole.long_miss | 38.5975–50.1094 | 38.1479–62.2835 | 11.42% | 20.65% | 1.055x |
| regex.cardinality.named.named.hit | 390.544–610.717 | 382.108–570.272 | 15.93% | 14.26% | 0.956x |
| regex.cardinality.named.anonymous.hit | 252.441–327.67 | 47.2744–66.3214 | 9.17% | 11.96% | 0.1748x |
| regex.cardinality.named.anonymous.long_miss | 156572–201437 | 47.4556–68.6358 | 8.67% | 12.94% | 0.0003103x |
| regex.cardinality.named.late.hit | 2541.65–4620.95 | 2316.33–6500.15 | 22.88% | 45.18% | 0.8936x |
| regex.cardinality.named.late.miss | 141.324–209.294 | 209.14–454.104 | 13.72% | 32.49% | 1.49x |
