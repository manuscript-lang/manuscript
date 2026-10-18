# Finite pinned standard lexical reuse: validation results

Clean baseline: `b49c0c99a3bc89176ce7598fbc1c53c651bfe770`. Clean candidate: `9c2296984c92a2f90c08c1353775150802765bae`. Both contain the same merged standard sources. All eight index/workspace build metadata files identify these exact commits with empty working diffs. No production code was changed by this measurement task.

**The measured warm benefit supports the finite lexical cache at its explicit fixed cost.** Every complete index/workspace payload matched, all strict selections remained, and warm index allocations fell about 14.43 MB per call. The cache retains about 4.858 MB (4.63 MiB) for this pinned inventory. Cold timings overlap; there is no startup improvement claim. Absolute sampled peak memory is not uniformly lower.

## Sources and complete behavior comparison

The actual merged inventory is **46 files, 303,169 source bytes, 35,727 tokens**; token capacity is 42,293 slots of 112 bytes, or 4,736,816 token-slot bytes. Source inventory SHA-256: `aa9a0469bbb766e1ad598564f45e59371bb3945a0c51f9e539001dc3e031c1f4`. Independent raw token-payload SHA-256: `9e02c9461d2c4d4300286b249495134f4364cd523b4a404b1539bc9f6b8d828b`. These match across baseline/candidate and all fixture sizes. Earlier 47-file measurements belong to the older main revision and are not used for this comparison.

Complete occurrence payloads include key/name, original position/end, declaration/write, every exported checker.Info field, stable Symbol/Binding/Method data, a deterministic full type graph, and declaration/argument source syntax with checker Fact cycles removed. Fixture roots alone are normalized; no pointer address is formatted. A coverage guard checks exported Info fields. Two fresh-process payloads per side/case match exactly, baseline equals candidate byte for byte, and flipping one occurrence write flag is rejected without changing occurrence count.

| Fixture | Occurrences | Full payload bytes | SHA-256 |
| --- | ---: | ---: | --- |
| app-41 | 5,706 | 12,118,703 | `45e0d1408d4adaf5c5f4078bec99a3f0b2effa80066c672510e5723ef6a1311f` |
| app-101 | 9,366 | 15,316,696 | `36726f43be2e9b2e4d11685e3aa5afd73bb02bf61da2e881ce0611fd8e180b93` |
| library-11 | 3,876 | 10,521,111 | `f16201dd91ee33a06a9f52930d1ff0d4772476190aaa7682e0dd22235d1c25cb` |
| library-21 | 4,486 | 11,053,193 | `a2f1c3086caecfdd08511f86b8362f40d5361a28974333f2a5db22d8f3f3b34b` |

All **108 complete workspace payload pairs** also match byte for byte (four fixtures × three operations × three modes × three requests). Hashes and unmodified payload assertions accompany each raw record. This compares returned symbols, reference locations and rename edit bodies, including URI/version/ranges; it does not merely compare lengths.

## Isolated warm sourceIndex

Five repeated benchmark samples per side/fixture, 500ms each, using the same checked fixture Program and one prewarming index outside the timer. Semantic serialization is outside timing. Values are medians; these are repeated benchmark observations, not independent process replicates.

| Fixture | Baseline ms/op | Candidate ms/op | Baseline B/op | Candidate B/op | Baseline allocs/op | Candidate allocs/op |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| app-41 | 19.16 | 12.17 | 25,081,309 | 10,648,591 | 82,577 | 54,513 |
| app-101 | 29.55 | 22.34 | 36,535,177 | 22,102,776 | 119,769 | 91,708 |
| library-11 | 13.86 | 5.86 | 19,405,432 | 4,973,639 | 63,999 | 35,934 |
| library-21 | 15.83 | 8.53 | 21,412,860 | 6,979,981 | 70,194 | 42,129 |

## First index and fixed retained cost

Each fresh process compiles the real fixture, then calls checker.StandardModules before GC/timing. That API checks all bundled source modules. StandardExports then filters already loaded symbols into a fresh map; its per-index map allocation remains part of the measured work equally. No sourceIndex or lexical-inventory lookup occurs before the first-index timer. The first index is dropped and GC completes before inventory inspection or any semantic serialization. The checked Program stays alive.

Five initial cold samples per side/fixture are retained in raw logs. For the application sizes, an additional **ten fresh processes per side** run in repeated ABBA order. The balanced observations supersede the initial apparent +2.6–4.4ms median penalty. No p95 or confidence claim is made.

| Application modules | Baseline cold median ms (range) | Candidate cold median ms (range) | Baseline mean ms | Candidate mean ms | Candidate minus baseline fixed retained bytes |
| --- | ---: | ---: | ---: | ---: | ---: |
| 41 | 25.40 (22.52–28.37) | 26.63 (23.12–29.55) | 25.38 | 26.57 | 4,857,896 |
| 101 | 40.15 (33.83–43.94) | 38.60 (34.72–44.52) | 39.60 | 39.12 | 4,858,144 |

The balanced medians differ by +1.23ms at 41 modules and −1.55ms at 101; ranges overlap. Candidate first-index total allocation is about 8 KB higher, since it performs the same initial lexing plus cache setup. Baseline post-GC heap decreases about 0.525 MB relative to its setup point; candidate increases about 4.333 MB. Their difference estimates the **4.858 MB fixed inventory cost** and is independent of project size. The candidate inventory has all 46 entries initialized, no lexical errors, and the exact token count/capacity above. Token-slot bytes exclude map/entry/allocation overhead, so they are not the whole retained cost.

## Warm workspace work and separate latency

Each mode/operation/size runs in a fresh process with one ordinary recovering open-document graph and its lazy index/lint warmed equally. Counts use observer overlays. Memory and latency binaries leave production function bodies unchanged and overlay only test code plus unused callback declarations. Latency has no callbacks or sampler. Full payload encoding occurs after the request timer/sampler stops. Three consecutive requests are measured per workload/process: n=3 repeated observations, with no independent-process percentile/CI claim. Values below are median handler milliseconds; transport framing/response encoding and editor-host latency are outside this measurement.

| Fixture | Operation | Strict compiles, both | Standard Lex calls baseline → candidate | Handler ms baseline → candidate |
| --- | --- | ---: | ---: | ---: |
| app-41 | symbols | 41 | 1,886 → 0 | 610.4 → 255.5 |
| app-41 | references | 41 | 1,886 → 0 | 522.2 → 246.4 |
| app-41 | rename | 122 | 1,840 → 0 | 492.3 → 248.4 |
| app-101 | symbols | 101 | 4,646 → 0 | 1444.3 → 604.5 |
| app-101 | references | 101 | 4,646 → 0 | 1206.6 → 557.7 |
| app-101 | rename | 302 | 4,600 → 0 | 1300.0 → 561.5 |
| library-11 | symbols | 11 | 506 → 0 | 184.7 → 99.9 |
| library-11 | references | 11 | 506 → 0 | 171.7 → 84.8 |
| library-11 | rename | 32 | 460 → 0 | 227.4 → 121.1 |
| library-21 | symbols | 21 | 966 → 0 | 437.1 → 277.0 |
| library-21 | references | 21 | 966 → 0 | 496.1 → 273.0 |
| library-21 | rename | 62 | 920 → 0 | 534.9 → 435.3 |

All compile/index counts and exact strict before/after selection counts match. Symbols/references still have no repeated exact selection within a request; rename keeps every original-source and modified-overlay validation. This optimization removes repeated immutable lexical work; it does not reuse checked Programs, Symbols, Types, methods, occurrences or validation success.

## Absolute warm and peak memory

The candidate warm baseline includes the fixed cache. The table therefore reports **absolute** heap/RSS and both warm-to-peak heap deltas. Each entry is the median of three request observations, MiB (1 MiB = 1,048,576 bytes). HeapAlloc and Linux process RSS are sampled every 2ms; observed maxima are lower bounds, not exact peaks. Sample counts and all absolute points are in summary/raw records. Sampling can affect scheduling; these elapsed times are not used for latency claims. RSS belongs to a Go test process and includes runtime page retention, not a shipped editor process.

| Fixture | Operation | Warm heap B → C | Peak heap B → C | Heap peak delta B → C | Warm RSS B → C | Peak RSS B → C | Samples/request B / C |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| app-41 | symbols | 13.03 → 17.66 | 46.01 → 44.60 | 33.00 → 26.95 | 46.84 → 44.35 | 58.10 → 55.81 | 251–267 / 120–138 |
| app-41 | references | 13.03 → 17.66 | 47.39 → 44.10 | 34.36 → 26.43 | 33.53 → 44.18 | 58.98 → 55.80 | 253–272 / 110–119 |
| app-41 | rename | 13.03 → 17.66 | 39.82 → 39.14 | 26.79 → 21.50 | 36.72 → 42.18 | 52.76 → 50.42 | 256–275 / 110–122 |
| app-101 | symbols | 18.50 → 23.13 | 75.03 → 62.76 | 56.56 → 39.63 | 54.48 → 58.99 | 88.42 → 76.98 | 609–635 / 285–292 |
| app-101 | references | 18.49 → 23.13 | 74.17 → 71.47 | 55.67 → 48.36 | 48.88 → 55.74 | 90.36 → 84.84 | 541–578 / 260–276 |
| app-101 | rename | 18.50 → 23.13 | 57.12 → 57.93 | 38.63 → 34.80 | 55.20 → 63.16 | 71.06 → 70.91 | 586–614 / 270–312 |
| library-11 | symbols | 10.29 → 14.92 | 37.50 → 33.70 | 27.21 → 18.77 | 29.50 → 36.79 | 50.80 → 45.11 | 95–107 / 47–55 |
| library-11 | references | 10.29 → 14.91 | 36.03 → 33.76 | 25.74 → 18.85 | 39.79 → 38.77 | 48.00 → 44.55 | 83–92 / 43–46 |
| library-11 | rename | 10.29 → 14.92 | 35.91 → 34.51 | 25.64 → 19.61 | 29.06 → 39.43 | 48.60 → 46.12 | 101–117 / 61–64 |
| library-21 | symbols | 11.22 → 15.85 | 44.44 → 40.93 | 33.09 → 25.08 | 36.95 → 43.86 | 56.47 → 52.37 | 216–236 / 134–141 |
| library-21 | references | 11.22 → 15.85 | 42.45 → 39.34 | 31.26 → 23.49 | 38.06 → 44.84 | 54.51 → 50.79 | 209–230 / 119–129 |
| library-21 | rename | 11.22 → 15.85 | 43.64 → 39.67 | 32.42 → 23.84 | 37.36 → 42.38 | 56.46 → 51.38 | 276–289 / 222–223 |

Peak memory is not uniformly reduced: 101-module rename has a sampled median absolute heap peak of 57.12 → 57.93 MiB despite a smaller delta above its warmer starting point. Its sampled RSS peaks are approximately unchanged. Other observed peak comparisons mostly improve, but GC/sampling variability and n=3 prevent a general peak-memory guarantee.

After three requests and close/invalidation, every URI/analysis/index/lint map is empty. Baseline final heap above the warmed pre-open baseline ranges from 13,616 to 283,312 bytes across memory-mode cases; candidate ranges from 4,866,488 to 4,882,472 bytes. The candidate intentionally retains the finite global token inventory after closing documents. This fixed retention is distinct from retaining checked workspace graphs.

## Reproduction, scope and artifacts

Use the commands and detailed methodology in README.md. Every run fixes GOMAXPROCS=4, GOGC=100, GOMEMLIMIT=off and uses pinned Go 1.25.1. Cold and warm runs are serial, with other local heavy jobs paused. There are 216 workspace handler measurements across baseline/candidate, plus five initial cold processes per side/fixture, five warm benchmark samples, two semantic-payload processes per side/fixture, independent token inventories, and 40 additional balanced cold processes.

Local executor directories retain complete JSON payloads and binaries for this validation. A portable publication copy intentionally omits these large/generated files, while preserving source/probe/adapter hashes, exact inputs, raw small logs, balanced records, full-payload digests and scripts to regenerate and recompare them. The published summary alone records successful comparisons; it is not a substitute for rerunning the preserved probes when input code or standard sources change.

The measured tradeoff favors this bounded immutable lexical cache. It does not justify checked-graph request caches, cross-program standard semantics, startup claims or broad memory-reduction claims. Root review, race/correctness tests and exact-head CI remain separate acceptance gates. CPU was released after all measurements completed.
