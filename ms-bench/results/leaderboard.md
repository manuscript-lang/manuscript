# ms-bench leaderboard

235 trials (1 errored and excluded). Pass rate counts all scored trials; tokens, turns, wall time and cost average over passing trials only. Ranked by pass rate, then cost.

### Languages (all models)

| rank | language | trials | pass | first build ok | tokens | turns | wall s | cost |
|---:|---|---:|---:|---:|---:|---:|---:|---:|
| 1 | Manuscript (cheat sheet) | 49 | 96% | 53% | 644k | 14.1 | 156.8 | $0.025 |
| 2 | Rust | 46 | 96% | 98% | 196k | 6.2 | 59.6 | $0.011 |
| 3 | TypeScript | 46 | 93% | 96% | 160k | 5.5 | 46.1 | $0.009 |
| 4 | Go | 46 | 93% | 67% | 177k | 6.0 | 50.7 | $0.010 |
| 5 | Manuscript | 47 | 85% | 53% | 1088k | 20.4 | 226.8 | $0.033 |

### Models (all languages)

| rank | agent / model | trials | pass | first build ok | tokens | turns | wall s | cost |
|---:|---|---:|---:|---:|---:|---:|---:|---:|
| 1 | claude-code / claude-haiku-5-5 | 234 | 93% | 73% | 447k | 10.3 | 107.0 | $0.018 |

### Model x language

| rank | model / language | trials | pass | first build ok | tokens | turns | wall s | cost |
|---:|---|---:|---:|---:|---:|---:|---:|---:|
| 1 | claude-haiku-5-5 / Manuscript (cheat sheet) | 49 | 96% | 53% | 644k | 14.1 | 156.8 | $0.025 |
| 2 | claude-haiku-5-5 / Rust | 46 | 96% | 98% | 196k | 6.2 | 59.6 | $0.011 |
| 3 | claude-haiku-5-5 / TypeScript | 46 | 93% | 96% | 160k | 5.5 | 46.1 | $0.009 |
| 4 | claude-haiku-5-5 / Go | 46 | 93% | 67% | 177k | 6.0 | 50.7 | $0.010 |
| 5 | claude-haiku-5-5 / Manuscript | 47 | 85% | 53% | 1088k | 20.4 | 226.8 | $0.033 |

### Where the input tokens go (passing trials, mean per trial)

Input tokens include cache reads. `base` is the system prompt plus the task, re-sent on every step, so it scales with turns; `docs` is the Manuscript docs bundle when the agent reads it;
`reads` is other file and command output; `build` is check/build/run output (compile-error retries); `writes` is edited code echoed back; `model output` is the agent's own text and tool calls.

| language | input | output | base | docs | reads | build | writes | model output |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| TypeScript | 151k | 8.6k | 122k | 0k | 0k | 6k | 0k | 23k |
| Go | 167k | 9.9k | 133k | 0k | 3k | 5k | 0k | 27k |
| Rust | 184k | 11.9k | 137k | 0k | 3k | 5k | 0k | 39k |
| Manuscript | 1063k | 24.6k | 451k | 274k | 29k | 32k | 1k | 275k |
| Manuscript (cheat sheet) | 622k | 22.4k | 315k | 17k | 45k | 42k | 1k | 202k |

### Category: abstraction

| rank | language | trials | pass | first build ok | tokens | turns | wall s | cost |
|---:|---|---:|---:|---:|---:|---:|---:|---:|
| 1 | TypeScript (provisional) | 1 | 100% | 100% | 163k | 5.0 | 71.2 | $0.014 |
| 2 | Rust (provisional) | 1 | 100% | 100% | 314k | 7.0 | 129.1 | $0.025 |
| 3 | Manuscript (cheat sheet) (provisional) | 1 | 100% | 0% | 710k | 15.0 | 137.4 | $0.029 |
| 4 | Go (provisional) | 1 | 0% | 0% | - | - | - | - |
| 5 | Manuscript (provisional) | 1 | 0% | 0% | - | - | - | - |

### Category: algorithms

| rank | language | trials | pass | first build ok | tokens | turns | wall s | cost |
|---:|---|---:|---:|---:|---:|---:|---:|---:|
| 1 | TypeScript (provisional) | 6 | 100% | 100% | 131k | 5.2 | 29.7 | $0.005 |
| 2 | Rust (provisional) | 6 | 100% | 100% | 138k | 5.3 | 32.9 | $0.006 |
| 3 | Manuscript (cheat sheet) (provisional) | 5 | 100% | 20% | 513k | 12.6 | 111.0 | $0.018 |
| 4 | Manuscript (provisional) | 6 | 100% | 67% | 1518k | 26.5 | 375.3 | $0.040 |
| 5 | Go (provisional) | 6 | 83% | 50% | 157k | 6.0 | 32.6 | $0.006 |

### Category: applications

| rank | language | trials | pass | first build ok | tokens | turns | wall s | cost |
|---:|---|---:|---:|---:|---:|---:|---:|---:|
| 1 | TypeScript | 15 | 93% | 87% | 215k | 6.4 | 66.8 | $0.013 |
| 2 | Go | 15 | 93% | 87% | 208k | 6.1 | 73.5 | $0.015 |
| 3 | Rust | 15 | 93% | 93% | 261k | 7.0 | 91.2 | $0.018 |
| 4 | Manuscript (cheat sheet) | 15 | 93% | 67% | 828k | 15.6 | 195.1 | $0.034 |
| 5 | Manuscript | 15 | 87% | 60% | 1226k | 20.2 | 254.9 | $0.042 |

### Category: data

| rank | language | trials | pass | first build ok | tokens | turns | wall s | cost |
|---:|---|---:|---:|---:|---:|---:|---:|---:|
| 1 | TypeScript (provisional) | 2 | 100% | 100% | 140k | 5.5 | 31.2 | $0.005 |
| 2 | Rust (provisional) | 2 | 100% | 100% | 145k | 5.5 | 37.1 | $0.006 |
| 3 | Go (provisional) | 2 | 100% | 50% | 148k | 5.5 | 37.4 | $0.006 |
| 4 | Manuscript (cheat sheet) (provisional) | 5 | 100% | 60% | 437k | 10.4 | 104.2 | $0.021 |
| 5 | Manuscript (provisional) | 2 | 100% | 50% | 719k | 15.5 | 91.9 | $0.023 |

### Category: data-formats

| rank | language | trials | pass | first build ok | tokens | turns | wall s | cost |
|---:|---|---:|---:|---:|---:|---:|---:|---:|
| 1 | TypeScript (provisional) | 3 | 100% | 100% | 141k | 5.3 | 44.7 | $0.008 |
| 2 | Rust (provisional) | 3 | 100% | 100% | 150k | 5.7 | 36.9 | $0.008 |
| 3 | Go (provisional) | 3 | 100% | 100% | 147k | 5.3 | 41.8 | $0.009 |
| 4 | Manuscript (cheat sheet) (provisional) | 3 | 100% | 67% | 568k | 14.7 | 105.7 | $0.020 |
| 5 | Manuscript (provisional) | 3 | 100% | 33% | 1479k | 27.7 | 258.1 | $0.040 |

### Category: data-structures

| rank | language | trials | pass | first build ok | tokens | turns | wall s | cost |
|---:|---|---:|---:|---:|---:|---:|---:|---:|
| 1 | TypeScript (provisional) | 5 | 100% | 100% | 120k | 5.0 | 22.1 | $0.004 |
| 2 | Rust (provisional) | 5 | 100% | 100% | 139k | 5.6 | 31.4 | $0.005 |
| 3 | Go (provisional) | 5 | 100% | 40% | 164k | 6.6 | 28.8 | $0.006 |
| 4 | Manuscript (cheat sheet) (provisional) | 5 | 100% | 20% | 641k | 17.0 | 200.2 | $0.020 |
| 5 | Manuscript (provisional) | 5 | 80% | 60% | 946k | 20.5 | 259.3 | $0.026 |

### Category: number-theory

| rank | language | trials | pass | first build ok | tokens | turns | wall s | cost |
|---:|---|---:|---:|---:|---:|---:|---:|---:|
| 1 | TypeScript (provisional) | 2 | 100% | 100% | 130k | 5.0 | 33.7 | $0.006 |
| 2 | Go (provisional) | 2 | 100% | 50% | 155k | 6.0 | 36.1 | $0.006 |
| 3 | Rust (provisional) | 2 | 100% | 100% | 190k | 6.5 | 50.2 | $0.009 |
| 4 | Manuscript (provisional) | 2 | 100% | 50% | 585k | 13.5 | 94.8 | $0.020 |
| 5 | Manuscript (cheat sheet) (provisional) | 2 | 100% | 50% | 946k | 21.5 | 266.4 | $0.031 |

### Category: parsing

| rank | language | trials | pass | first build ok | tokens | turns | wall s | cost |
|---:|---|---:|---:|---:|---:|---:|---:|---:|
| 1 | TypeScript (provisional) | 3 | 100% | 100% | 194k | 5.7 | 83.3 | $0.015 |
| 2 | Go (provisional) | 3 | 100% | 67% | 230k | 6.3 | 88.9 | $0.017 |
| 3 | Rust (provisional) | 3 | 100% | 100% | 279k | 7.0 | 102.1 | $0.020 |
| 4 | Manuscript (cheat sheet) (provisional) | 3 | 100% | 67% | 1021k | 17.0 | 243.2 | $0.036 |
| 5 | Manuscript (provisional) | 3 | 67% | 67% | 908k | 16.0 | 156.9 | $0.035 |

### Category: state-machines

| rank | language | trials | pass | first build ok | tokens | turns | wall s | cost |
|---:|---|---:|---:|---:|---:|---:|---:|---:|
| 1 | Go (provisional) | 1 | 100% | 100% | 157k | 5.0 | 64.1 | $0.011 |
| 2 | Rust (provisional) | 1 | 100% | 100% | 199k | 6.0 | 66.7 | $0.012 |
| 3 | Manuscript (cheat sheet) (provisional) | 2 | 100% | 100% | 444k | 10.0 | 120.7 | $0.024 |
| 4 | Manuscript (provisional) | 1 | 100% | 100% | 633k | 12.0 | 133.1 | $0.029 |
| 5 | TypeScript (provisional) | 1 | 0% | 100% | - | - | - | - |

### Category: strings

| rank | language | trials | pass | first build ok | tokens | turns | wall s | cost |
|---:|---|---:|---:|---:|---:|---:|---:|---:|
| 1 | TypeScript (provisional) | 4 | 100% | 100% | 113k | 4.5 | 26.3 | $0.005 |
| 2 | Rust (provisional) | 4 | 100% | 100% | 153k | 5.8 | 32.4 | $0.006 |
| 3 | Go (provisional) | 4 | 100% | 25% | 180k | 6.8 | 35.0 | $0.007 |
| 4 | Manuscript (cheat sheet) (provisional) | 4 | 100% | 50% | 445k | 12.2 | 111.4 | $0.016 |
| 5 | Manuscript (provisional) | 4 | 75% | 25% | 758k | 18.0 | 140.7 | $0.021 |

### Category: text

| rank | language | trials | pass | first build ok | tokens | turns | wall s | cost |
|---:|---|---:|---:|---:|---:|---:|---:|---:|
| 1 | Go (provisional) | 4 | 100% | 100% | 123k | 5.0 | 24.9 | $0.005 |
| 2 | Manuscript (provisional) | 5 | 80% | 40% | 725k | 18.0 | 113.2 | $0.020 |
| 3 | TypeScript (provisional) | 4 | 75% | 100% | 103k | 4.3 | 22.0 | $0.004 |
| 4 | Rust (provisional) | 4 | 75% | 100% | 121k | 5.0 | 24.5 | $0.005 |
| 5 | Manuscript (cheat sheet) (provisional) | 4 | 75% | 50% | 234k | 7.7 | 52.0 | $0.010 |

### Tier 1

| rank | language | trials | pass | first build ok | tokens | turns | wall s | cost |
|---:|---|---:|---:|---:|---:|---:|---:|---:|
| 1 | TypeScript (provisional) | 6 | 100% | 100% | 112k | 4.7 | 22.9 | $0.004 |
| 2 | Rust (provisional) | 6 | 100% | 100% | 131k | 5.3 | 25.3 | $0.004 |
| 3 | Go (provisional) | 6 | 100% | 50% | 159k | 6.3 | 25.9 | $0.005 |
| 4 | Manuscript (provisional) | 7 | 100% | 29% | 685k | 17.0 | 110.3 | $0.019 |
| 5 | Manuscript (cheat sheet) (provisional) | 6 | 83% | 50% | 369k | 11.2 | 115.2 | $0.012 |

### Tier 2

| rank | language | trials | pass | first build ok | tokens | turns | wall s | cost |
|---:|---|---:|---:|---:|---:|---:|---:|---:|
| 1 | Go | 19 | 100% | 53% | 155k | 5.8 | 37.4 | $0.007 |
| 2 | Manuscript (cheat sheet) | 19 | 100% | 47% | 533k | 13.4 | 141.8 | $0.021 |
| 3 | TypeScript | 19 | 95% | 100% | 131k | 5.1 | 33.1 | $0.006 |
| 4 | Rust | 19 | 95% | 95% | 167k | 5.9 | 44.4 | $0.008 |
| 5 | Manuscript | 19 | 84% | 63% | 885k | 18.2 | 203.4 | $0.027 |

### Tier 3

| rank | language | trials | pass | first build ok | tokens | turns | wall s | cost |
|---:|---|---:|---:|---:|---:|---:|---:|---:|
| 1 | Manuscript (cheat sheet) | 24 | 96% | 58% | 796k | 15.3 | 178.2 | $0.032 |
| 2 | Rust | 21 | 95% | 100% | 242k | 6.7 | 83.6 | $0.016 |
| 3 | TypeScript | 21 | 90% | 90% | 202k | 6.2 | 65.6 | $0.013 |
| 4 | Go | 21 | 86% | 86% | 207k | 6.1 | 73.0 | $0.014 |
| 5 | Manuscript | 21 | 81% | 52% | 1444k | 23.8 | 296.8 | $0.046 |
