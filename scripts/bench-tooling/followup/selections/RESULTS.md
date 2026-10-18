# Strict-selection reuse and workspace memory measurements

Exact production commit: `5facbb5ff966904e0b6fe918245d7df7885937ff`. Both matrix builds report an empty working diff. The probes are external Go overlays only. No production or repository-test file was edited and no graph cache was implemented.

Application fixtures have one main importing 40 or 100 leaf modules, with 20 functions per leaf. Library controls have the same star source shape with 10 or 20 leaves and no manifest entry; each strict selected root therefore discovers the full source graph. Each process starts with one ordinary recovering open-document snapshot and its lazy index/lint. Sources stay unchanged across requests; rename returns validated edits without applying them.

Each size/operation/mode has one fresh test process and three consecutive requests. Count and memory modes use separate processes. This is 72 measured requests across 24 matrix processes, plus a six-request small pilot. The three requests are repeated observations in one process, not independent process replicates; no confidence interval or percentile is claimed. GOMAXPROCS=4, GOGC=100, GOMEMLIMIT=off; checkout-pinned Go 1.25.1.

## Exact work counts

Counts are identical across all three requests in each workload. Selection identity includes CompileFile input path and SHA-256 of the complete compiler.Options value, including the complete effective overlay after the requested-source override. The controlled fixture has stable disk contents; equal keys here are evidence about this fixture, not proof that a real request freezes filesystem inputs. Strict before/after rename groups are separate.

| Fixture | Operation | Strict compiles | Before calls / unique / repeats | After calls / unique / repeats | New indexes | Indexed project modules | Standard lex calls / source bytes |
| --- | --- | ---: | --- | --- | ---: | ---: | ---: |
| Application 41 | references | 41 | 41 / 41 / 0 | 0 / 0 / 0 | 41 | 81 | 1,927 / 12,434,316 |
| Application 41 | rename | 122 | 81 / 41 / 40 | 41 / 41 / 0 | 40 | 40 | 1,880 / 12,131,040 |
| Application 41 | symbols | 41 | 41 / 41 / 0 | 0 / 0 / 0 | 41 | 81 | 1,927 / 12,434,316 |
| Application 101 | references | 101 | 101 / 101 / 0 | 0 / 0 / 0 | 101 | 201 | 4,747 / 30,630,876 |
| Application 101 | rename | 302 | 201 / 101 / 100 | 101 / 101 / 0 | 100 | 100 | 4,700 / 30,327,600 |
| Application 101 | symbols | 101 | 101 / 101 / 0 | 0 / 0 / 0 | 101 | 201 | 4,747 / 30,630,876 |
| Library 11 | references | 11 | 11 / 11 / 0 | 0 / 0 / 0 | 11 | 121 | 517 / 3,336,036 |
| Library 11 | rename | 32 | 21 / 11 / 10 | 11 / 11 / 0 | 10 | 110 | 470 / 3,032,760 |
| Library 11 | symbols | 11 | 11 / 11 / 0 | 0 / 0 / 0 | 11 | 121 | 517 / 3,336,036 |
| Library 21 | references | 21 | 21 / 21 / 0 | 0 / 0 / 0 | 21 | 441 | 987 / 6,368,796 |
| Library 21 | rename | 62 | 41 / 21 / 20 | 21 / 21 / 0 | 20 | 420 | 940 / 6,065,520 |
| Library 21 | symbols | 21 | 21 / 21 / 0 | 0 / 0 / 0 | 21 | 441 | 987 / 6,368,796 |

All compile calls in these measured requests were strict calls. The live initial document index is already reused: rename creates N-1 new indexes while symbols/references create N. Every new source index re-lexes the same 47 checked standard modules, totaling 303,276 standard source bytes per index. The result payload checks passed: application symbol counts 800/2000, library counts 200/400, three cross-file references, and three rename edits in exactly two documents.

## Memory observations

The table shows increases above each request’s forced-GC warm starting point. Memory mode leaves all counting callbacks nil and constructs no selection maps. A goroutine samples HeapAlloc and Linux process RSS every 2ms; observed maxima are lower bounds on peaks. ReadMemStats/RSS sampling can perturb scheduling, so elapsed time is retained only in raw data. The binary includes nil observer branches and the Go test harness: absolute process RSS is not a shipped CLI or editor-host measurement. RSS also reflects Go page retention and prior requests.

| Fixture | Operation | Sampled peak heap increase, MiB range | Sampled peak RSS increase, MiB range | Post-GC request heap change, KiB range | Samples per request |
| --- | --- | ---: | ---: | ---: | ---: |
| Application 41 | references | 33.43–34.99 | 14.76–26.18 | -1.66–2.04 | 261–282 |
| Application 41 | rename | 25.92–27.68 | 10.68–15.04 | -2.06–2.17 | 258–285 |
| Application 41 | symbols | 34.89–36.36 | 11.71–28.25 | -2.13–4.80 | 273–281 |
| Application 101 | references | 48.97–60.75 | 30.00–36.53 | -2.48–7.07 | 586–648 |
| Application 101 | rename | 38.74–42.34 | 15.05–27.93 | -2.40–3.16 | 595–640 |
| Application 101 | symbols | 55.80–59.10 | 33.23–44.26 | -0.95–7.71 | 593–675 |
| Library 11 | references | 24.96–25.56 | 11.42–19.20 | -2.00–1.92 | 86–94 |
| Library 11 | rename | 25.47–28.44 | 19.11–20.98 | 7.07–14.41 | 99–103 |
| Library 11 | symbols | 26.29–27.44 | 12.12–22.73 | -1.97–1.66 | 93–95 |
| Library 21 | references | 29.80–33.68 | 3.25–26.09 | -1.67–7.21 | 209–224 |
| Library 21 | rename | 30.60–32.72 | 15.21–25.46 | -2.19–24.05 | 291–312 |
| Library 21 | symbols | 32.29–34.36 | 12.96–25.02 | -0.94–4.27 | 230–237 |

After three requests and close/invalidation, every process reported zero URI-cache, analysis, index and lint entries. For memory-mode application runs, final heap was 14,008–23,064 bytes above the warmed pre-open baseline; library runs were 9,888–22,400 bytes above baseline. These small harness/runtime residuals do not establish a retained checked-graph trend. Post-request observations likewise show no megabyte-scale accumulation; the larger library rename residual reaches 24,624 bytes. No peak graph or index was intentionally retained by observers.

## Decision supported by this evidence

- Reject a general request-local selected-graph cache for symbols/references: each exact strict selection occurs once per request, so it offers no measured hit on either application or library fixtures. The same synthetic inputs repeat across the three requests, but cross-request reuse is a different design with filesystem/generation obligations.
- Rename has N-1 exact before-selection repeats, separated by the entire collection phase. Its N after-overlay checks are distinct and cannot use before results. Retaining every collection graph to capture those hits would retain many checked owners; the library control demonstrates that each owner contains all N project modules (index module work 121→441 for 11→21 selections). This is concrete graph amplification evidence, not a measurement of an implemented N-graph cache. A bounded one-owner cache would need a demonstrated ordering-local hit and fresh strict validation; these results do not establish one.
- Repeated lexing of the finite pinned standard source is a separate, measurable candidate: 1,927/4,747 calls and 12.43/30.63 MB of standard text per application symbols/references request. This supports investigating immutable lexical/header reuse while preserving per-Program checked identities. Counts alone do not quantify the latency gain; benchmark any proposed implementation before accepting it.
- Keep the current transient strict workspace checks and complete rename validation. The existing initial index reuse is active and verified by index counts. No broader architecture was implemented by this measurement subtask.

## Reproduction and artifacts

Commands are in [README.md](README.md). The published `application-5facbb5f` and `library-5facbb5f` directories contain `inputs.json` with exact SHA/source/probe digests, empty `working-tree.patch`, `build.log`, raw individual process logs (including every exact-selection record) and `summary.json`. The executor also retained generated overlay files, binaries, combined records and the pilot; those are regenerated rather than committed.

CPU was released to the parent immediately after both matrices completed. No measurement remains running.
