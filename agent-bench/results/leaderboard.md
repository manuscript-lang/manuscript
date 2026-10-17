# agent-bench leaderboard

76 trials (0 errored and excluded). Pass rate counts all scored trials; tokens, turns, wall time and cost average over passing trials only. Ranked by pass rate, then cost.

### Languages (all models)

| rank | language | trials | pass | first build ok | tokens | turns | wall s | cost |
|---:|---|---:|---:|---:|---:|---:|---:|---:|
| 1 | Rust | 19 | 79% | 95% | 490k | 7.1 | 185.2 | $0.075 |
| 2 | Manuscript | 19 | 79% | 74% | 5074k | 36.2 | 581.5 | $0.414 |
| 3 | TypeScript | 19 | 74% | 100% | 633k | 7.8 | 199.3 | $0.076 |
| 4 | Go | 19 | 74% | 74% | 948k | 9.4 | 330.6 | $0.133 |

### Models (all languages)

| rank | agent / model | trials | pass | first build ok | tokens | turns | wall s | cost |
|---:|---|---:|---:|---:|---:|---:|---:|---:|
| 1 | claude-code / claude-haiku-5-5 | 76 | 76% | 86% | 1821k | 15.4 | 326.2 | $0.177 |

### Model x language

| rank | model / language | trials | pass | first build ok | tokens | turns | wall s | cost |
|---:|---|---:|---:|---:|---:|---:|---:|---:|
| 1 | claude-haiku-5-5 / Rust | 19 | 79% | 95% | 490k | 7.1 | 185.2 | $0.075 |
| 2 | claude-haiku-5-5 / Manuscript | 19 | 79% | 74% | 5074k | 36.2 | 581.5 | $0.414 |
| 3 | claude-haiku-5-5 / TypeScript | 19 | 74% | 100% | 633k | 7.8 | 199.3 | $0.076 |
| 4 | claude-haiku-5-5 / Go | 19 | 74% | 74% | 948k | 9.4 | 330.6 | $0.133 |

### Where the input tokens go (passing trials, mean per trial)

Input tokens include cache reads. `base` is the system prompt plus the task, re-sent on every step, so it scales with turns; `docs` is the Manuscript docs bundle when the agent reads it;
`reads` is other file and command output; `build` is check/build/run output (compile-error retries); `writes` is edited code echoed back; `model output` is the agent's own text and tool calls.

| language | input | output | base | docs | reads | build | writes | model output |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| TypeScript | 588k | 44.1k | 193k | 0k | 1k | 23k | 1k | 371k |
| Go | 884k | 63.9k | 219k | 0k | 16k | 8k | 1k | 640k |
| Rust | 447k | 43.3k | 174k | 0k | 7k | 8k | 0k | 257k |
| Manuscript | 4988k | 86.4k | 887k | 644k | 232k | 91k | 2k | 3131k |

### Category: algorithms

| rank | language | trials | pass | first build ok | tokens | turns | wall s | cost |
|---:|---|---:|---:|---:|---:|---:|---:|---:|
| 1 | TypeScript (provisional) | 3 | 100% | 100% | 142k | 5.3 | 35.4 | $0.006 |
| 2 | Rust (provisional) | 3 | 100% | 100% | 143k | 5.3 | 38.7 | $0.007 |
| 3 | Manuscript (provisional) | 3 | 100% | 67% | 2120k | 34.0 | 572.7 | $0.057 |
| 4 | Go (provisional) | 3 | 67% | 67% | 184k | 6.5 | 42.5 | $0.008 |

### Category: applications

| rank | language | trials | pass | first build ok | tokens | turns | wall s | cost |
|---:|---|---:|---:|---:|---:|---:|---:|---:|
| 1 | TypeScript (provisional) | 12 | 67% | 100% | 1007k | 9.8 | 325.3 | $0.130 |
| 2 | Rust (provisional) | 12 | 67% | 92% | 792k | 8.8 | 312.3 | $0.134 |
| 3 | Go (provisional) | 12 | 67% | 75% | 1541k | 12.2 | 547.2 | $0.228 |
| 4 | Manuscript (provisional) | 12 | 67% | 75% | 8426k | 48.4 | 821.4 | $0.745 |

### Category: data

| rank | language | trials | pass | first build ok | tokens | turns | wall s | cost |
|---:|---|---:|---:|---:|---:|---:|---:|---:|
| 1 | TypeScript (provisional) | 1 | 100% | 100% | 123k | 5.0 | 24.1 | $0.004 |
| 2 | Rust (provisional) | 1 | 100% | 100% | 127k | 5.0 | 32.5 | $0.005 |
| 3 | Go (provisional) | 1 | 100% | 100% | 132k | 5.0 | 34.2 | $0.005 |
| 4 | Manuscript (provisional) | 1 | 100% | 100% | 482k | 12.0 | 71.1 | $0.017 |

### Category: parsing

| rank | language | trials | pass | first build ok | tokens | turns | wall s | cost |
|---:|---|---:|---:|---:|---:|---:|---:|---:|
| 1 | TypeScript (provisional) | 1 | 100% | 100% | 128k | 5.0 | 31.6 | $0.005 |
| 2 | Rust (provisional) | 1 | 100% | 100% | 130k | 5.0 | 31.1 | $0.006 |
| 3 | Go (provisional) | 1 | 100% | 0% | 158k | 6.0 | 36.3 | $0.006 |
| 4 | Manuscript (provisional) | 1 | 100% | 100% | 508k | 13.0 | 77.4 | $0.017 |

### Category: state-machines

| rank | language | trials | pass | first build ok | tokens | turns | wall s | cost |
|---:|---|---:|---:|---:|---:|---:|---:|---:|
| 1 | Go (provisional) | 1 | 100% | 100% | 157k | 5.0 | 64.1 | $0.011 |
| 2 | Rust (provisional) | 1 | 100% | 100% | 199k | 6.0 | 66.7 | $0.012 |
| 3 | Manuscript (provisional) | 1 | 100% | 100% | 633k | 12.0 | 133.1 | $0.029 |
| 4 | TypeScript (provisional) | 1 | 0% | 100% | - | - | - | - |

### Category: strings

| rank | language | trials | pass | first build ok | tokens | turns | wall s | cost |
|---:|---|---:|---:|---:|---:|---:|---:|---:|
| 1 | TypeScript (provisional) | 1 | 100% | 100% | 126k | 5.0 | 25.4 | $0.004 |
| 2 | Go (provisional) | 1 | 100% | 100% | 130k | 5.0 | 31.3 | $0.005 |
| 3 | Rust (provisional) | 1 | 100% | 100% | 131k | 5.0 | 33.0 | $0.006 |
| 4 | Manuscript (provisional) | 1 | 100% | 0% | 718k | 17.0 | 151.0 | $0.021 |

### Tier 2

| rank | language | trials | pass | first build ok | tokens | turns | wall s | cost |
|---:|---|---:|---:|---:|---:|---:|---:|---:|
| 1 | TypeScript (provisional) | 4 | 100% | 100% | 119k | 4.8 | 27.8 | $0.005 |
| 2 | Go (provisional) | 4 | 100% | 50% | 135k | 5.2 | 29.9 | $0.005 |
| 3 | Rust (provisional) | 4 | 100% | 100% | 134k | 5.2 | 31.5 | $0.006 |
| 4 | Manuscript (provisional) | 4 | 100% | 75% | 870k | 18.2 | 270.5 | $0.024 |

### Tier 3

| rank | language | trials | pass | first build ok | tokens | turns | wall s | cost |
|---:|---|---:|---:|---:|---:|---:|---:|---:|
| 1 | Rust (provisional) | 5 | 100% | 100% | 166k | 5.6 | 51.3 | $0.010 |
| 2 | Manuscript (provisional) | 5 | 100% | 80% | 1313k | 22.0 | 260.6 | $0.042 |
| 3 | TypeScript (provisional) | 5 | 80% | 100% | 142k | 5.2 | 36.1 | $0.007 |
| 4 | Go (provisional) | 5 | 80% | 80% | 179k | 6.0 | 54.1 | $0.010 |

### Tier 5

| rank | language | trials | pass | first build ok | tokens | turns | wall s | cost |
|---:|---|---:|---:|---:|---:|---:|---:|---:|
| 1 | TypeScript (provisional) | 10 | 60% | 100% | 1302k | 11.5 | 422.4 | $0.170 |
| 2 | Rust (provisional) | 10 | 60% | 90% | 998k | 9.7 | 399.2 | $0.175 |
| 3 | Go (provisional) | 10 | 60% | 80% | 2002k | 14.5 | 715.4 | $0.301 |
| 4 | Manuscript (provisional) | 10 | 60% | 70% | 11011k | 60.0 | 1056.2 | $0.985 |
