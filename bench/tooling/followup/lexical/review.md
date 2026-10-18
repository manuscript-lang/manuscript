# Independent exact production and evidence review: lexical reuse

**ACCEPT `9c2296984c92a2f90c08c1353775150802765bae`**, compared with clean baseline `b49c0c99a3bc89176ce7598fbc1c53c651bfe770`. No remaining correctness, concurrency, lifetime or measured-benefit blocker found. Final publication/evidence-only commit still requires an exact-head refresh. CI status remains a separate gate.

Review was read-only: production diff and consumer trace, tests, approved proposal, lexical/README.md, RESULTS.md, probes/adapters/preparation/runner/summary scripts, raw index/workspace payloads and measurement metadata, protocol/assertion/race/mutation evidence. No source/test implementation or Go/timed runs performed. Lightweight independent Python checked metadata, payload bytes and arithmetic without rewriting retained evidence.

## Production contract

The entire production change remains one sourceIndex lex-call substitution and the private39-line inventory helper. Inventory keys and retained filename/source values come solely from checker.StandardModules. The corrected closure calls lexer.Lex(pinned.file, pinned.source), avoiding first-caller filename backing-storage retention. No Program, Module, Symbol, Type, Method, occurrence Info, request source or semantic success is stored in the cache. Only finite pinned lexical values/error state are retained.

An actual hit requires exact filename and source-value equality. An @std prefix merely gates lookup. Unknown canonical-looking names, modified source and disk filenames lex directly and cannot grow or poison the key set. Initialization is lazy; sync.OnceValue publishes the fixed map, and per-entry sync.Once publishes token/error data before every return. There is no concurrent checker, invalidation owner or checked-graph cache. Private sourceIndex is the sole production consumer and only reads returned token slices; it preserves its original module order, successful-lex assignment, duplicate-file map semantics and header-position fallback. Tokens remain ordinary lexer values with original positions. Public checker detached-documentation/mutable-caller contracts are untouched.

Checked symbol/type identities and scope selection remain per original Program. Strict selected checks, rename before/after checks, overlay/path resolution, cancellation checkpoints and open-document generation lifetimes are unchanged. No N selected Programs are retained. This satisfies the narrow accepted design and preserves the rejected/do-nothing decision for general strict-graph reuse.

## Tests and complete behavior evidence

Production tests compare full lexer token values for every pinned file, require repeated slice identity on hits, compare exact direct-lexer fallback outputs/errors for modified valid/malformed text, unknown name and disk path, require finite keys after100 unknown inputs, and verify fallback does not poison a real entry. Concurrent-first-use coverage does not reset global state and is meaningful in its separate fresh -run process. Source-equality mutation fails the intended modified-input comparison rather than a setup error.

Retained exact-candidate full LSP race log passes13.111s; separate fresh initialization race passes1.847s. Repo-check passes. Built-server protocol evidence reports16 complete before/after payloads equal. Type-definition in that wire fixture is null on both sides, so that particular payload is an equivalence check rather than positive type-definition coverage; broader LSP tests remain the coverage for that feature. Native assertion controls retain explicit success/failure/ignored-result exits0/1/0. These executions were performed by parent/measurement agents, not rerun by this reviewer.

Independently confirmed all eight index/workspace metadata records identify the expected baseline/candidate exact commits and empty tracked working diffs. Four fixture index payloads are byte-identical baseline/candidate and across two fresh self-runs per side, with sizes/digests matching RESULTS.md. The serializer covers every current exported Info field, full exported Type/Definition graphs and stable semantic identity, while omitting checker Fact cycles from source syntax and normalizing only fixture roots. It has a write-flag mutation control. Independently compared all108 complete workspace payload pairs, covering symbols/references/rename across counts/memory/latency modes and three requests each. All are byte-identical. This evidence is much stronger than equal occurrence/result lengths.

## Benefit and disclosed cost

Independently recomputed the five warm benchmark medians per side/fixture and balanced cold medians from40 fresh-process ABBA records; they reproduce summary.json. Current merged inputs are46 pinned files/303,169 source bytes/35,727 tokens, not the previous revision's47-file inventory. Baseline and candidate source/token digests match. Fixed token-slot capacity42,293×112=4,736,816 bytes is distinguished from the approximately4.858MB total post-GC incremental inventory cost.

Warm index timing improves on each fixture, and allocations decrease approximately14.43MB per index. Workspace handler improvements are reported separately from instrumented count and sampled-memory runs; strict compile/selection counts stay unchanged and warm repeated standard lexing disappears. Full request payloads remain complete. The measured warm gains justify this small finite cache against doing nothing without claiming graph reuse.

Cold application observations overlap: balanced medians are+1.23ms and−1.55ms; no startup improvement or statistical confidence claim is made. Fixed process retention survives document close by design. All lifecycle cache maps are empty after close/invalidation, while candidate final heap retains the finite lexical inventory. The report correctly shows absolute memory as well as warm-to-peak deltas: app101 rename sampled absolute heap peak rises57.12→57.93MiB, so there is no universal peak-memory reduction claim. Two-millisecond maxima are lower bounds, repeated workspace samples are n=3 in one process, and isolated warm samples are not independent process replicas. No p95/editor-host/transport claim is inferred.

## Remaining gates

Refresh this acceptance for the final artifact-only head after verifying the production/test tree is unchanged and publication probes/report preserve these qualifications. CI must pass on that exact head. No additional architecture, compiler optimization, cache expansion or non-LSP implementation is required by this review.
