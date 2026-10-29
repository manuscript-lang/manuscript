Seven process medians per variant, each from 5 timed samples. CV uses the population standard deviation of process medians. Ranges are process-median ranges, not individual-sample bounds. The paired-ratio median is diagnostic; results.md retains the canonical ratio of medians.

| case | before min–max ns | after min–max ns | before CV | after CV | paired-ratio median |
| --- | ---: | ---: | ---: | ---: | ---: |
| regex.cardinality.whole.0 | 34.1292–56.4207 | 34.7148–69.2962 | 18.69% | 22.97% | 1.228x |
| regex.cardinality.whole.1 | 422.962–569.746 | 248.811–709.056 | 10.91% | 42.39% | 0.7371x |
| regex.cardinality.whole.128 | 42398.1–53349.1 | 23986.7–80556.2 | 9.04% | 53.11% | 0.6421x |
| regex.cardinality.whole.2000 | 613041–713953 | 348414–1.37981e+06 | 5.30% | 56.64% | 0.7203x |
| regex.cardinality.grouped.1 | 605.326–737.986 | 567.09–1016.35 | 7.28% | 22.91% | 1.012x |
| regex.cardinality.grouped.2000 | 866284–1.06888e+06 | 843300–2.70022e+06 | 7.53% | 47.36% | 1.09x |
| regex.cardinality.whole.long | 758622–881858 | 367681–876581 | 4.90% | 29.80% | 0.6012x |
| regex.cardinality.whole.empty_matches | 817.24–1114.68 | 529.514–1125.35 | 10.48% | 30.11% | 0.8756x |
| regex.cardinality.whole.over_limit | 272.479–986.226 | 261.3–718.78 | 62.79% | 42.71% | 1.082x |
| regex.cardinality.first.whole.hit | 268.858–1412.2 | 192.248–425.008 | 83.67% | 33.74% | 0.8033x |
| regex.cardinality.first.whole.miss | 52.3188–197.862 | 31.3561–52.2186 | 59.06% | 19.31% | 0.5597x |
| regex.cardinality.first.grouped.hit | 390.602–859.288 | 369.678–535.764 | 32.41% | 12.47% | 1.048x |
| regex.cardinality.first.whole.long | 414616–866646 | 410398–1.05092e+06 | 30.35% | 38.73% | 1.112x |
| regex.cardinality.named.whole.hit | 228.329–527.949 | 34.4227–74.903 | 37.30% | 34.20% | 0.1548x |
| regex.cardinality.named.whole.long_miss | 160351–287501 | 34.0241–66.2904 | 22.26% | 23.52% | 0.0002202x |
| regex.cardinality.named.named.hit | 401.501–577.077 | 419.047–614.498 | 12.87% | 12.67% | 1.101x |
| regex.cardinality.named.anonymous.hit | 258.08–348.723 | 36.2286–55.4968 | 10.20% | 16.70% | 0.1585x |
| regex.cardinality.named.anonymous.long_miss | 156765–316250 | 38.2269–112.687 | 26.37% | 43.59% | 0.000272x |
| regex.cardinality.named.late.hit | 2756.42–5410.4 | 2881.48–5325.71 | 24.46% | 19.00% | 0.9873x |
| regex.cardinality.named.late.miss | 150.486–338.301 | 142.218–322.113 | 33.00% | 33.40% | 0.9603x |
