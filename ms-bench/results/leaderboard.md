# ms-bench leaderboard

12 trials (0 errored and excluded). Pass rate counts all scored trials; tokens, turns, wall time and cost average over passing trials only. Ranked by pass rate, then cost.

### Languages (all models)

| rank | language | trials | pass | first build ok | tokens | turns | wall s | cost |
|---:|---|---:|---:|---:|---:|---:|---:|---:|
| 1 | TypeScript (provisional) | 3 | 100% | 100% | 110k | 4.7 | 20.6 | $0.003 |
| 2 | Go (provisional) | 4 | 100% | 75% | 121k | 5.0 | 23.2 | $0.003 |
| 3 | Rust (provisional) | 3 | 100% | 100% | 120k | 5.0 | 25.4 | $0.004 |
| 4 | Manuscript (provisional) | 2 | 100% | 50% | 414k | 11.5 | 52.5 | $0.013 |

### Models (all languages)

| rank | agent / model | trials | pass | first build ok | tokens | turns | wall s | cost |
|---:|---|---:|---:|---:|---:|---:|---:|---:|
| 1 | claude-code / claude-haiku-5-5 (provisional) | 12 | 100% | 83% | 167k | 6.0 | 28.0 | $0.005 |

### Model x language

| rank | model / language | trials | pass | first build ok | tokens | turns | wall s | cost |
|---:|---|---:|---:|---:|---:|---:|---:|---:|
| 1 | claude-haiku-5-5 / TypeScript (provisional) | 3 | 100% | 100% | 110k | 4.7 | 20.6 | $0.003 |
| 2 | claude-haiku-5-5 / Go (provisional) | 4 | 100% | 75% | 121k | 5.0 | 23.2 | $0.003 |
| 3 | claude-haiku-5-5 / Rust (provisional) | 3 | 100% | 100% | 120k | 5.0 | 25.4 | $0.004 |
| 4 | claude-haiku-5-5 / Manuscript (provisional) | 2 | 100% | 50% | 414k | 11.5 | 52.5 | $0.013 |

### Where the input tokens go (passing trials, mean per trial)

Input tokens include cache reads. `base` is the system prompt plus the task; `docs` is the Manuscript docs bundle when the agent reads it;
`reads` is other file and command output; `build` is check/build/run output (compile-error retries); `writes` is edited code echoed back; `model output` is the agent's own text and tool calls.

| language | input | output | base | docs | reads | build | writes | model output |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| TypeScript | 108k | 2.5k | 100k | 0k | 0k | 4k | 0k | 4k |
| Go | 118k | 3.1k | 107k | 0k | 0k | 4k | 0k | 7k |
| Rust | 117k | 3.6k | 107k | 0k | 1k | 3k | 0k | 6k |
| Manuscript | 407k | 6.9k | 246k | 120k | 3k | 7k | 0k | 31k |

### Category: algorithms

| rank | language | trials | pass | first build ok | tokens | turns | wall s | cost |
|---:|---|---:|---:|---:|---:|---:|---:|---:|
| 1 | TypeScript (provisional) | 1 | 100% | 100% | 116k | 5.0 | 19.2 | $0.003 |
| 2 | Go (provisional) | 1 | 100% | 0% | 142k | 6.0 | 22.7 | $0.003 |
| 3 | Rust (provisional) | 1 | 100% | 100% | 119k | 5.0 | 25.2 | $0.003 |
| 4 | Manuscript (provisional) | 1 | 100% | 100% | 392k | 11.0 | 48.4 | $0.011 |

### Category: data

| rank | language | trials | pass | first build ok | tokens | turns | wall s | cost |
|---:|---|---:|---:|---:|---:|---:|---:|---:|
| 1 | TypeScript (provisional) | 1 | 100% | 100% | 123k | 5.0 | 24.1 | $0.004 |
| 2 | Rust (provisional) | 1 | 100% | 100% | 127k | 5.0 | 32.5 | $0.005 |
| 3 | Go (provisional) | 1 | 100% | 100% | 132k | 5.0 | 34.2 | $0.005 |

### Category: data-structures

| rank | language | trials | pass | first build ok | tokens | turns | wall s | cost |
|---:|---|---:|---:|---:|---:|---:|---:|---:|
| 1 | Go (provisional) | 1 | 100% | 100% | 143k | 6.0 | 21.7 | $0.004 |

### Category: text

| rank | language | trials | pass | first build ok | tokens | turns | wall s | cost |
|---:|---|---:|---:|---:|---:|---:|---:|---:|
| 1 | Go (provisional) | 1 | 100% | 100% | 68k | 3.0 | 14.4 | $0.002 |
| 2 | TypeScript (provisional) | 1 | 100% | 100% | 91k | 4.0 | 18.4 | $0.002 |
| 3 | Rust (provisional) | 1 | 100% | 100% | 115k | 5.0 | 18.5 | $0.002 |
| 4 | Manuscript (provisional) | 1 | 100% | 0% | 436k | 12.0 | 56.7 | $0.015 |

### Tier 1

| rank | language | trials | pass | first build ok | tokens | turns | wall s | cost |
|---:|---|---:|---:|---:|---:|---:|---:|---:|
| 1 | TypeScript (provisional) | 2 | 100% | 100% | 104k | 4.5 | 18.8 | $0.002 |
| 2 | Go (provisional) | 2 | 100% | 50% | 105k | 4.5 | 18.6 | $0.002 |
| 3 | Rust (provisional) | 2 | 100% | 100% | 117k | 5.0 | 21.9 | $0.003 |
| 4 | Manuscript (provisional) | 2 | 100% | 50% | 414k | 11.5 | 52.5 | $0.013 |

### Tier 2

| rank | language | trials | pass | first build ok | tokens | turns | wall s | cost |
|---:|---|---:|---:|---:|---:|---:|---:|---:|
| 1 | TypeScript (provisional) | 1 | 100% | 100% | 123k | 5.0 | 24.1 | $0.004 |
| 2 | Go (provisional) | 2 | 100% | 100% | 137k | 5.5 | 28.0 | $0.005 |
| 3 | Rust (provisional) | 1 | 100% | 100% | 127k | 5.0 | 32.5 | $0.005 |
