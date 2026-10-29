Seven process medians per variant, each from 3 timed samples. CV uses the population standard deviation of process medians. Ranges are process-median ranges, not individual-sample bounds. The paired-ratio median is diagnostic; results.md retains the canonical ratio of medians.

| case | before min–max ns | after min–max ns | before CV | after CV | paired-ratio median |
| --- | ---: | ---: | ---: | ---: | ---: |
| regex.cardinality.whole.0 | 32.4427–47.8368 | 33.4192–38.4549 | 14.78% | 4.68% | 1.031x |
| regex.cardinality.whole.1 | 387.946–485.616 | 235.378–269.726 | 7.34% | 5.17% | 0.5875x |
| regex.cardinality.whole.128 | 38103.4–53362.7 | 23102.4–33754.3 | 10.77% | 14.76% | 0.6325x |
| regex.cardinality.whole.2000 | 577233–726877 | 334905–461209 | 8.64% | 11.14% | 0.5818x |
| regex.cardinality.grouped.1 | 541.871–753.6 | 533.9–1667.27 | 10.84% | 51.23% | 0.986x |
| regex.cardinality.grouped.2000 | 831666–1.14751e+06 | 803825–1.44153e+06 | 10.58% | 21.67% | 0.9563x |
| regex.cardinality.whole.long | 731207–1.04374e+06 | 373953–456661 | 12.90% | 6.47% | 0.5091x |
| regex.cardinality.whole.empty_matches | 744.203–1066.53 | 510.32–671.732 | 12.66% | 9.11% | 0.6857x |
| regex.cardinality.whole.over_limit | 242.746–341.182 | 235.459–489.798 | 11.92% | 30.61% | 0.972x |
| regex.cardinality.first.whole.hit | 245.762–350.148 | 171.212–221.086 | 12.88% | 8.51% | 0.6943x |
| regex.cardinality.first.whole.miss | 50.248–67.1889 | 26.1312–37.5986 | 10.07% | 11.49% | 0.5696x |
| regex.cardinality.first.grouped.hit | 348.865–496.931 | 361.09–911.764 | 11.08% | 40.19% | 0.9905x |
| regex.cardinality.first.whole.long | 384254–522494 | 374966–654371 | 11.05% | 21.24% | 1.036x |
| regex.cardinality.named.whole.hit | 203.645–288.943 | 34.3764–46.9529 | 14.34% | 11.59% | 0.1688x |
| regex.cardinality.named.whole.long_miss | 153656–367708 | 33.5737–53.9484 | 35.01% | 16.93% | 0.0002132x |
| regex.cardinality.named.named.hit | 385.853–653.985 | 385.706–624.48 | 19.13% | 18.15% | 0.9713x |
