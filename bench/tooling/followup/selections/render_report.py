#!/usr/bin/env python3
import json,pathlib
root=pathlib.Path(__file__).resolve().parent
sets={label:json.loads((root/label/'summary.json').read_text()) for label in ['application-5facbb5f','library-5facbb5f']}
lines=['# Strict-selection reuse and workspace memory measurements','',
'Exact production commit: `5facbb5ff966904e0b6fe918245d7df7885937ff`. Both matrix builds report an empty working diff. The probes are external Go overlays only. No production or repository-test file was edited and no graph cache was implemented.','',
'Application fixtures have one main importing 40 or 100 leaf modules, with 20 functions per leaf. Library controls have the same star source shape with 10 or 20 leaves and no manifest entry; each strict selected root therefore discovers the full source graph. Each process starts with one ordinary recovering open-document snapshot and its lazy index/lint. Sources stay unchanged across requests; rename returns validated edits without applying them.','',
'Each size/operation/mode has one fresh test process and three consecutive requests. Count and memory modes use separate processes. This is 72 measured requests across 24 matrix processes, plus a six-request small pilot. The three requests are repeated observations in one process, not independent process replicates; no confidence interval or percentile is claimed. GOMAXPROCS=4, GOGC=100, GOMEMLIMIT=off; checkout-pinned Go 1.25.1.','',
'## Exact work counts','',
'Counts are identical across all three requests in each workload. Selection identity includes CompileFile input path and SHA-256 of the complete compiler.Options value, including the complete effective overlay after the requested-source override. The controlled fixture has stable disk contents; equal keys here are evidence about this fixture, not proof that a real request freezes filesystem inputs. Strict before/after rename groups are separate.','',
'| Fixture | Operation | Strict compiles | Before calls / unique / repeats | After calls / unique / repeats | New indexes | Indexed project modules | Standard lex calls / source bytes |',
'| --- | --- | ---: | --- | --- | ---: | ---: | ---: |']
for label,data in sets.items():
 for r in data['summary']:
  if r['mode']!='counts':continue
  c=r['counters'][0];b=r['strict_phases']['before'][0];a=r['strict_phases']['after'][0]
  phase=lambda p:f"{p['calls']} / {p['unique']} / {p['repeated_calls']}"
  lines.append(f"| {'Library' if r['library'] else 'Application'} {r['modules']} | {r['operation']} | {c['strict_calls']} | {phase(b)} | {phase(a)} | {c['index_calls']} | {c['index_project_modules']} | {c['standard_lex_calls']:,} / {c['standard_lex_bytes']:,} |")
lines += ['',
'All compile calls in these measured requests were strict calls. The live initial document index is already reused: rename creates N-1 new indexes while symbols/references create N. Every new source index re-lexes the same 47 checked standard modules, totaling 303,276 standard source bytes per index. The result payload checks passed: application symbol counts 800/2000, library counts 200/400, three cross-file references, and three rename edits in exactly two documents.','',
'## Memory observations','',
'The table shows increases above each request’s forced-GC warm starting point. Memory mode leaves all counting callbacks nil and constructs no selection maps. A goroutine samples HeapAlloc and Linux process RSS every 2ms; observed maxima are lower bounds on peaks. ReadMemStats/RSS sampling can perturb scheduling, so elapsed time is retained only in raw data. The binary includes nil observer branches and the Go test harness: absolute process RSS is not a shipped CLI or editor-host measurement. RSS also reflects Go page retention and prior requests.','',
'| Fixture | Operation | Sampled peak heap increase, MiB range | Sampled peak RSS increase, MiB range | Post-GC request heap change, KiB range | Samples per request |',
'| --- | --- | ---: | ---: | ---: | ---: |']
fmt=lambda nums,div:f'{min(nums)/div:.2f}–{max(nums)/div:.2f}'
for label,data in sets.items():
 for r in data['summary']:
  if r['mode']!='memory':continue
  lines.append(f"| {'Library' if r['library'] else 'Application'} {r['modules']} | {r['operation']} | {fmt(r['peak_heap_deltas'],1048576)} | {fmt(r['peak_rss_deltas'],1048576)} | {fmt(r['postgc_heap_deltas'],1024)} | {min(r['sample_counts'])}–{max(r['sample_counts'])} |")
lines += ['',
'After three requests and close/invalidation, every process reported zero URI-cache, analysis, index and lint entries. For memory-mode application runs, final heap was 14,008–23,064 bytes above the warmed pre-open baseline; library runs were 9,888–22,400 bytes above baseline. These small harness/runtime residuals do not establish a retained checked-graph trend. Post-request observations likewise show no megabyte-scale accumulation; the larger library rename residual reaches 24,624 bytes. No peak graph or index was intentionally retained by observers.','',
'## Decision supported by this evidence','',
'- Reject a general request-local selected-graph cache for symbols/references: each exact strict selection occurs once per request, so it offers no measured hit on either application or library fixtures. The same synthetic inputs repeat across the three requests, but cross-request reuse is a different design with filesystem/generation obligations.','- Rename has N-1 exact before-selection repeats, separated by the entire collection phase. Its N after-overlay checks are distinct and cannot use before results. Retaining every collection graph to capture those hits would retain many checked owners; the library control demonstrates that each owner contains all N project modules (index module work 121→441 for 11→21 selections). This is concrete graph amplification evidence, not a measurement of an implemented N-graph cache. A bounded one-owner cache would need a demonstrated ordering-local hit and fresh strict validation; these results do not establish one.','- Repeated lexing of the finite pinned standard source is a separate, measurable candidate: 1,927/4,747 calls and 12.43/30.63 MB of standard text per application symbols/references request. This supports investigating immutable lexical/header reuse while preserving per-Program checked identities. Counts alone do not quantify the latency gain; benchmark any proposed implementation before accepting it.','- Keep the current transient strict workspace checks and complete rename validation. The existing initial index reuse is active and verified by index counts. No broader architecture was implemented by this measurement subtask.','',
'## Reproduction and artifacts','',
'Commands are in [README.md](README.md). Every matrix directory contains `inputs.json` with exact SHA/source/probe digests, empty `working-tree.patch`, generated overlay files and nil hooks, `build.log`, the test binary, individual process logs, full exact-selection records in `measurements.json`, and `summary.json`. The pilot is under `pilot-5facbb5f`; principal matrices are `application-5facbb5f` and `library-5facbb5f`.','',
'CPU was released to the parent immediately after both matrices completed. No measurement remains running.']
(root/'RESULTS.md').write_text('\n'.join(lines)+'\n')
print(root/'RESULTS.md')
