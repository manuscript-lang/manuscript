#!/usr/bin/env python3
import json,pathlib
root=pathlib.Path(__file__).resolve().parent;s=json.loads((root/'summary.json').read_text())
lexer=s['metadata']['baseline-index']['source_sha256']['pkg/lexer/lexer.go'];parser=s['metadata']['baseline-index']['source_sha256']['pkg/parser/parser.go']
lines=['# Integration addendum: lexical cache with the newer lexer','',
'Baseline: **55228347c8555186ab6a483459e161e1bef82326** (the lexer/plain-text parser performance change). Candidate: **3232c8db008fe60804f88bb8a243d15ce8da0a14** (the merged lexical cache, whose direct parent is that baseline). Both are clean detached worktrees with the same pinned SDK/build payload setup. No production or repository-test changes were made by this refresh.','',
'This bounded refresh updates the cache tradeoff after a new lexer changed allocation behavior. The earlier [full lexical report](../lexical/RESULTS.md) remains historical evidence for b49c0c99 → 9c229698; its figures are not relabeled as current-main measurements.','',
'## Current inputs and behavior','',
f'Lexer source SHA-256, equal on both sides: `{lexer}`. Parser source SHA-256: `{parser}`. Complete pinned standard source inventory SHA-256: `{s["std_source_sha256"]}`. Raw standard-token payload SHA-256: `{s["token_payload_sha256"]}`. All exact commit/source/probe/adapter hashes and empty working-diff proofs are retained in inputs.json files.','',
'The inventory remains **46 files / 303,169 source bytes / 35,727 tokens**, with token capacity **42,293 slots × 112 bytes = 4,736,816 token-slot bytes**. Token capacity did not change. The post-GC fixed-retention estimate did change, so the earlier 4.858 MB estimate is superseded for this lexer pair.','',
'Both complete sourceIndex payloads match byte for byte, with two fresh-process self-comparisons per side and every exported Info field covered. The two payloads are 5,706 occurrences / 12,118,703 bytes and 9,366 occurrences / 15,316,696 bytes. Their digests are in summary.json and match the historical payload digests too. One-write-flag mutants are rejected without changing occurrence count. All **12 complete symbols payload pairs** also match; counts are 800/2,000 symbols.','',
'## Warm index and fixed cache cost','',
'Three 300ms warm benchmark samples per side/fixture; medians below are descriptive repeated observations. Fixture setup, initial prewarming index and full semantic serialization remain outside timing. Each cold result has five fresh-process samples; compiler fixture plus StandardModules warms the existing standard loader equally before GC/timing, and no sourceIndex/cache lookup occurs before the cold timer. The index is dropped and GC completes before inventory inspection.','',
'| Modules | Warm ms/op B → C | B/op B → C | Allocs/op B → C | Fixed retained bytes, C minus B |','| --- | ---: | ---: | ---: | ---: |']
for x in s['index']:
 b=x['baseline'];c=x['candidate'];lines.append(f'| {x["case"]} | {b["warm_median_ns"]/1e6:.3f} → {c["warm_median_ns"]/1e6:.3f} | {b["warm_median_bytes"]:,} → {c["warm_median_bytes"]:,} | {b["warm_median_allocations"]:,} → {c["warm_median_allocations"]:,} | {x["fixed_retained_difference"]:,} |')
lines += ['',
'The current cache saves about **14.327 MB allocated per warm index** and about **1,582 allocation events per index**. The old lexer comparison saved about 28,064 allocation events; that count must not be reused after the lexer update. Fixed retained cache cost is now about **4.746 MB (4.53 MiB)**, around 112 KB below the historical estimate, even though token capacity remains the same. This estimate includes inventory/allocation overhead; token-slot bytes alone are not the whole cache.','',
'| Modules | Cold median ms (range), baseline | Cold median ms (range), candidate | First-index allocated bytes B → C |','| --- | ---: | ---: | ---: |']
for x in s['index']:
 b=x['baseline'];c=x['candidate'];fmt=lambda v:f'{v["cold_median_ms"]:.3f} ({v["cold_range_ms"][0]:.3f}–{v["cold_range_ms"][1]:.3f})';lines.append(f'| {x["case"]} | {fmt(b)} | {fmt(c)} | {b["cold_median_bytes"]:,} → {c["cold_median_bytes"]:,} |')
lines += ['',
'These five-per-side cold observations are sequential descriptive samples, not a new counterbalanced startup study. They do not establish a general cold/startup improvement or regression. Raw samples are retained; no p95 or confidence claim is made.','',
'## Plain symbols handler refresh','',
'Three consecutive requests in one fresh process per size/mode/side. Count and latency processes are separate. Plain latency overlays no production function bodies, uses no counter callbacks or sampler, and excludes payload encoding/transport framing. Full returned payloads are normalized/persisted after the timer.','',
'| Modules | Handler median ms B → C | Strict compiles, both | New indexes, both | Standard Lex calls B → C |','| --- | ---: | ---: | ---: | ---: |']
for x in s['symbols']:
 b=x['counts']['baseline'];c=x['counts']['candidate'];lines.append(f'| {x["case"]} | {x["latency"]["baseline"]["median_ms"]:.3f} → {x["latency"]["candidate"]["median_ms"]:.3f} | {b["strict_calls"]} | {b["index_calls"]} | {b["standard_lex_calls"]:,} → {c["standard_lex_calls"]:,} |')
lines += ['',
'Every strict root and complete symbols payload is preserved. The cache removes warmed standard lexing; it does not remove checking. This refresh intentionally does not repeat the full references/rename/library/peak-memory campaign. Historical peak and all-operation tables stay dated to their original pair. Current fixed retention is measured separately above; no current absolute peak-memory claim is inferred from latency or allocation savings.','',
'## Reproduction and artifact limits','',
'Use README.md commands. All runs use checkout-pinned Go 1.25.1, GOMAXPROCS=4, GOGC=100, GOMEMLIMIT=off. No other local heavy jobs ran during measurements. There are 20 fresh cold processes, 12 warm benchmark samples, eight first-index full-payload processes, two independent token inventories, and 24 symbols handler measurements (12 before/after pairs). CPU was released immediately after the bounded run.','',
'The portable addendum includes scripts and .go.txt templates, summary, small raw logs/cold records, input hashes and empty working patches. Full JSON payloads and binaries remain on the original executor and can be regenerated; published hashes record the successful original byte comparisons. verify_published.py checks the reduced artifact without claiming to regenerate omitted bytes. Source checkouts, payload setup and writable GOCACHE are configurable. The parent owns exact-head correctness/CI and documentation integration.']
(root/'RESULTS.md').write_text('\n'.join(lines)+'\n');print(root/'RESULTS.md')
