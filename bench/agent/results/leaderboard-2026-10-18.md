# agent-bench leaderboard

80 trials (0 errored and excluded). Pass rate counts all scored trials; tokens, turns, wall time and cost average over passing trials only. `agent tokens` is what the agent consumed (input including cache reads, plus output). `solution size (tokens)` is the number of lexical tokens (identifiers, literals, punctuation; comments excluded) in the final source it wrote, mean over passing trials; `n/a` means the run predates the measurement. Ranked by pass rate, then cost.

### Languages (all models)

| rank | language | trials | pass | first build ok | agent tokens | solution size (tokens) | turns | wall s | cost |
|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | TypeScript | 20 | 95% | 80% | 710k | 3451 | 8.4 | 214.8 | $0.096 |
| 2 | Rust | 20 | 90% | 85% | 538k | 4202 | 7.4 | 213.4 | $0.102 |
| 3 | Go | 20 | 90% | 80% | 673k | 4389 | 8.4 | 210.8 | $0.103 |
| 4 | Manuscript | 20 | 65% | 45% | 4468k | 6311 | 33.8 | 451.8 | $0.378 |

### Models (all languages)

| rank | agent / model | trials | pass | first build ok | agent tokens | solution size (tokens) | turns | wall s | cost |
|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | claude-code / claude-haiku-5-5 | 80 | 85% | 72% | 1373k | 4445 | 13.0 | 258.7 | $0.153 |

### Model x language

| rank | model / language | trials | pass | first build ok | agent tokens | solution size (tokens) | turns | wall s | cost |
|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | claude-haiku-5-5 / TypeScript | 20 | 95% | 80% | 710k | 3451 | 8.4 | 214.8 | $0.096 |
| 2 | claude-haiku-5-5 / Rust | 20 | 90% | 85% | 538k | 4202 | 7.4 | 213.4 | $0.102 |
| 3 | claude-haiku-5-5 / Go | 20 | 90% | 80% | 673k | 4389 | 8.4 | 210.8 | $0.103 |
| 4 | claude-haiku-5-5 / Manuscript | 20 | 65% | 45% | 4468k | 6311 | 33.8 | 451.8 | $0.378 |

### Where the input tokens go (passing trials, mean per trial)

Input tokens include cache reads. `base` is the system prompt plus the task, re-sent on every step, so it scales with turns; `docs` is the Manuscript docs bundle when the agent reads it;
`reads` is other file and command output; `build` is check/build/run output (compile-error retries); `writes` is edited code echoed back; `model output` is the agent's own text and tool calls.

| language | input | output | base | docs | reads | build | writes | model output |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| TypeScript | 660k | 50.0k | 211k | 0k | 5k | 31k | 1k | 412k |
| Go | 624k | 49.4k | 209k | 0k | 14k | 10k | 1k | 390k |
| Rust | 485k | 52.6k | 180k | 0k | 10k | 6k | 0k | 288k |
| Manuscript | 4372k | 96.0k | 861k | 0k | 429k | 147k | 4k | 2930k |

### Category: algorithms

| rank | language | trials | pass | first build ok | agent tokens | solution size (tokens) | turns | wall s | cost |
|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | TypeScript (provisional) | 3 | 100% | 100% | 129k | 962 | 5.0 | 24.7 | $0.006 |
| 2 | Go (provisional) | 3 | 100% | 67% | 171k | 937 | 6.3 | 30.5 | $0.008 |
| 3 | Rust (provisional) | 3 | 100% | 100% | 197k | 1160 | 7.0 | 34.7 | $0.009 |
| 4 | Manuscript (provisional) | 3 | 67% | 0% | 682k | 1250 | 16.5 | 101.0 | $0.022 |

### Category: applications

| rank | language | trials | pass | first build ok | agent tokens | solution size (tokens) | turns | wall s | cost |
|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | TypeScript (provisional) | 12 | 92% | 67% | 1130k | 5253 | 10.8 | 351.1 | $0.161 |
| 2 | Rust (provisional) | 12 | 83% | 83% | 825k | 6545 | 8.3 | 353.4 | $0.176 |
| 3 | Go (provisional) | 12 | 83% | 92% | 1081k | 7097 | 10.3 | 350.6 | $0.179 |
| 4 | Manuscript (provisional) | 12 | 67% | 67% | 6824k | 9430 | 44.8 | 665.6 | $0.600 |

### Category: data

| rank | language | trials | pass | first build ok | agent tokens | solution size (tokens) | turns | wall s | cost |
|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | TypeScript (provisional) | 2 | 100% | 100% | 121k | 979 | 4.5 | 30.2 | $0.006 |
| 2 | Go (provisional) | 2 | 100% | 100% | 180k | 1002 | 6.5 | 40.5 | $0.008 |
| 3 | Rust (provisional) | 2 | 100% | 50% | 198k | 1303 | 6.5 | 47.9 | $0.010 |
| 4 | Manuscript (provisional) | 2 | 100% | 50% | 843k | 1492 | 18.0 | 127.2 | $0.028 |

### Category: parsing

| rank | language | trials | pass | first build ok | agent tokens | solution size (tokens) | turns | wall s | cost |
|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | Rust (provisional) | 1 | 100% | 100% | 125k | 1276 | 5.0 | 19.6 | $0.006 |
| 2 | Go (provisional) | 1 | 100% | 0% | 127k | 837 | 5.0 | 34.7 | $0.007 |
| 3 | TypeScript (provisional) | 1 | 100% | 100% | 156k | 1067 | 6.0 | 25.1 | $0.007 |
| 4 | Manuscript (provisional) | 1 | 100% | 0% | 433k | 1122 | 12.0 | 92.8 | $0.017 |

### Category: state-machines

| rank | language | trials | pass | first build ok | agent tokens | solution size (tokens) | turns | wall s | cost |
|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | TypeScript (provisional) | 1 | 100% | 100% | 111k | 1299 | 4.0 | 35.6 | $0.009 |
| 2 | Rust (provisional) | 1 | 100% | 100% | 155k | 2030 | 5.0 | 52.0 | $0.011 |
| 3 | Go (provisional) | 1 | 100% | 100% | 155k | 1726 | 5.0 | 50.5 | $0.012 |
| 4 | Manuscript (provisional) | 1 | 0% | 0% | - | n/a | - | - | - |

### Category: strings

| rank | language | trials | pass | first build ok | agent tokens | solution size (tokens) | turns | wall s | cost |
|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | TypeScript (provisional) | 1 | 100% | 100% | 152k | 582 | 6.0 | 23.0 | $0.006 |
| 2 | Go (provisional) | 1 | 100% | 0% | 160k | 661 | 6.0 | 31.0 | $0.008 |
| 3 | Rust (provisional) | 1 | 100% | 100% | 164k | 791 | 6.0 | 36.1 | $0.008 |
| 4 | Manuscript (provisional) | 1 | 0% | 0% | - | n/a | - | - | - |

### Tier 2

| rank | language | trials | pass | first build ok | agent tokens | solution size (tokens) | turns | wall s | cost |
|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | TypeScript (provisional) | 4 | 100% | 100% | 119k | 646 | 4.8 | 20.0 | $0.005 |
| 2 | Go (provisional) | 4 | 100% | 50% | 147k | 728 | 5.8 | 27.1 | $0.007 |
| 3 | Rust (provisional) | 4 | 100% | 100% | 130k | 927 | 5.0 | 27.9 | $0.007 |
| 4 | Manuscript (provisional) | 4 | 75% | 0% | 575k | 1068 | 14.3 | 83.5 | $0.019 |

### Tier 3

| rank | language | trials | pass | first build ok | agent tokens | solution size (tokens) | turns | wall s | cost |
|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | TypeScript (provisional) | 6 | 100% | 83% | 142k | 1205 | 5.2 | 34.2 | $0.008 |
| 2 | Go (provisional) | 6 | 100% | 83% | 167k | 1253 | 5.8 | 41.6 | $0.009 |
| 3 | Rust (provisional) | 6 | 100% | 83% | 203k | 1544 | 6.7 | 47.0 | $0.011 |
| 4 | Manuscript (provisional) | 6 | 67% | 17% | 800k | 1527 | 17.5 | 124.0 | $0.028 |

### Tier 5

| rank | language | trials | pass | first build ok | agent tokens | solution size (tokens) | turns | wall s | cost |
|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | TypeScript (provisional) | 10 | 90% | 70% | 1351k | 6196 | 12.1 | 421.7 | $0.195 |
| 2 | Rust (provisional) | 10 | 80% | 80% | 993k | 7833 | 9.1 | 431.1 | $0.217 |
| 3 | Go (provisional) | 10 | 80% | 90% | 1316k | 8572 | 11.6 | 429.6 | $0.222 |
| 4 | Manuscript (provisional) | 10 | 60% | 80% | 8859k | 12122 | 54.3 | 854.5 | $0.792 |
