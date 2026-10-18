# Integration addendum: lexical cache with the newer lexer

Baseline: **55228347c8555186ab6a483459e161e1bef82326** (the lexer/plain-text parser performance change). Candidate: **3232c8db008fe60804f88bb8a243d15ce8da0a14** (the merged lexical cache, whose direct parent is that baseline). Both are clean detached worktrees with the same pinned SDK/build payload setup. No production or repository-test changes were made by this refresh.

This bounded refresh updates the cache tradeoff after a new lexer changed allocation behavior. The earlier [full lexical report](../lexical/RESULTS.md) remains historical evidence for b49c0c99 → 9c229698; its figures are not relabeled as current-main measurements.

## Current inputs and behavior

Lexer source SHA-256, equal on both sides: `bd46ad5d2eb1dd820003df196f850366ac24beb77c034fd16bdad0da0ee34256`. Parser source SHA-256: `adb191bed1ed27ec6fdb10b4a851463cb6139467d2e1dbd76e7633f5ae7be396`. Complete pinned standard source inventory SHA-256: `aa9a0469bbb766e1ad598564f45e59371bb3945a0c51f9e539001dc3e031c1f4`. Raw standard-token payload SHA-256: `9e02c9461d2c4d4300286b249495134f4364cd523b4a404b1539bc9f6b8d828b`. All exact commit/source/probe/adapter hashes and empty working-diff proofs are retained in inputs.json files.

The inventory remains **46 files / 303,169 source bytes / 35,727 tokens**, with token capacity **42,293 slots × 112 bytes = 4,736,816 token-slot bytes**. Token capacity did not change. The post-GC fixed-retention estimate did change, so the earlier 4.858 MB estimate is superseded for this lexer pair.

Both complete sourceIndex payloads match byte for byte, with two fresh-process self-comparisons per side and every exported Info field covered. The two payloads are 5,706 occurrences / 12,118,703 bytes and 9,366 occurrences / 15,316,696 bytes. Their digests are in summary.json and match the historical payload digests too. One-write-flag mutants are rejected without changing occurrence count. All **12 complete symbols payload pairs** also match; counts are 800/2,000 symbols.

## Warm index and fixed cache cost

Three 300ms warm benchmark samples per side/fixture; medians below are descriptive repeated observations. Fixture setup, initial prewarming index and full semantic serialization remain outside timing. Each cold result has five fresh-process samples; compiler fixture plus StandardModules warms the existing standard loader equally before GC/timing, and no sourceIndex/cache lookup occurs before the cold timer. The index is dropped and GC completes before inventory inspection.

| Modules | Warm ms/op B → C | B/op B → C | Allocs/op B → C | Fixed retained bytes, C minus B |
| --- | ---: | ---: | ---: | ---: |
| app-41 | 18.257 → 11.292 | 24,877,034 → 10,550,186 | 47,402 → 45,820 | 4,745,656 |
| app-101 | 29.875 → 25.436 | 36,282,893 → 21,956,329 | 72,595 → 71,014 | 4,745,208 |

The current cache saves about **14.327 MB allocated per warm index** and about **1,582 allocation events per index**. The old lexer comparison saved about 28,064 allocation events; that count must not be reused after the lexer update. Fixed retained cache cost is now about **4.746 MB (4.53 MiB)**, around 112 KB below the historical estimate, even though token capacity remains the same. This estimate includes inventory/allocation overhead; token-slot bytes alone are not the whole cache.

| Modules | Cold median ms (range), baseline | Cold median ms (range), candidate | First-index allocated bytes B → C |
| --- | ---: | ---: | ---: |
| app-41 | 23.654 (21.510–24.853) | 24.140 (21.892–27.163) | 24,878,496 → 24,887,208 |
| app-101 | 36.618 (33.972–39.593) | 39.604 (34.888–42.060) | 36,284,768 → 36,292,768 |

These five-per-side cold observations are sequential descriptive samples, not a new counterbalanced startup study. They do not establish a general cold/startup improvement or regression. Raw samples are retained; no p95 or confidence claim is made.

## Plain symbols handler refresh

Three consecutive requests in one fresh process per size/mode/side. Count and latency processes are separate. Plain latency overlays no production function bodies, uses no counter callbacks or sampler, and excludes payload encoding/transport framing. Full returned payloads are normalized/persisted after the timer.

| Modules | Handler median ms B → C | Strict compiles, both | New indexes, both | Standard Lex calls B → C |
| --- | ---: | ---: | ---: | ---: |
| app-41 | 529.466 → 228.648 | 41 | 41 | 1,886 → 0 |
| app-101 | 1291.530 → 670.113 | 101 | 101 | 4,646 → 0 |

Every strict root and complete symbols payload is preserved. The cache removes warmed standard lexing; it does not remove checking. This refresh intentionally does not repeat the full references/rename/library/peak-memory campaign. Historical peak and all-operation tables stay dated to their original pair. Current fixed retention is measured separately above; no current absolute peak-memory claim is inferred from latency or allocation savings.

## Reproduction and artifact limits

Use README.md commands. All runs use checkout-pinned Go 1.25.1, GOMAXPROCS=4, GOGC=100, GOMEMLIMIT=off. No other local heavy jobs ran during measurements. There are 20 fresh cold processes, 12 warm benchmark samples, eight first-index full-payload processes, two independent token inventories, and 24 symbols handler measurements (12 before/after pairs). CPU was released immediately after the bounded run.

The portable addendum includes scripts and .go.txt templates, summary, small raw logs/cold records, input hashes and empty working patches. Full JSON payloads and binaries remain on the original executor and can be regenerated; published hashes record the successful original byte comparisons. verify_published.py checks the reduced artifact without claiming to regenerate omitted bytes. Source checkouts, payload setup and writable GOCACHE are configurable. The parent owns exact-head correctness/CI and documentation integration.
