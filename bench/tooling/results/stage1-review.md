# Stage 1 independent exact-commit review

**Disposition: ACCEPT — no blocking correctness finding in exact head `1072850b4e2a551e6929bb3c80584db0e529121a`.**

Reviewed against base `a988705cbd5ed9c7424ac891aa42893c2805474a` in the clean detached checkout `/workspace/manuscript-tooling-stage1`. This verdict applies only to that two-file diff. It is a static implementation review, not a claim that CI or performance validation passed.

The original production diff at `aa7da0c54a3ec5ff9445741830dd7d9293aa76e9` was reviewed in full. The follow-up delta to the accepted head was then read in full: it adds only the parameter-classification assertion described below. The combined diff still changes only the same two files, with 105 additions and one deletion.

## Scope and evidence

Read current `AGENTS.md`, manuscript-change/tooling guidance, relevant expert routing and standard-document lessons, and the complete exact diff. Traced `semantic`, `moduleFile`, `module`, `standardLibraryDocument`, `sourceModules`, and `sourceIndex`, plus existing standard-library/editor tests.

Commands included:

```sh
git rev-parse HEAD
git rev-parse a988705c
git status --short
git diff --name-status a988705c 1072850b4e2a551e6929bb3c80584db0e529121a
git diff a988705c aa7da0c5 -- pkg/tooling/lsp/semantic.go pkg/tooling/lsp/performance_test.go
git diff aa7da0c54a3ec5ff9445741830dd7d9293aa76e9 1072850b4e2a551e6929bb3c80584db0e529121a
git diff --check a988705c 1072850b4e2a551e6929bb3c80584db0e529121a
```

Whitespace validation succeeded, and the checkout was clean. No tests, compilation, benchmarks, mutations of the checkout, pushes, or external comments were performed, per the request to avoid interference with the parent's measurements.

## Correctness assessment

The production change at `pkg/tooling/lsp/semantic.go:42-45` moves the same `moduleFile(checked[0], d)` lookup immediately before the occurrence loop. The document and compiler result do not change during that loop. `sourceIndex` constructs its own token/index/maps, reads checked facts, sorts the newly built index, and does not replace the result's module graph. Filtering, classification precedence, offsets, ordering, lexical fallback, and the later expression pass are unchanged.

| Case | Static result |
| --- | --- |
| No checked argument | The guard remains unchanged; lexical classification is unchanged. |
| Checked result with nil Program | `module` returns nil before standard-library or filesystem work (`analysis.go:64-67`), and `moduleFile` returns empty string (`editor.go:450-455`). `sourceIndex` still returns an empty index. The newly evaluated lookup is safe. |
| Virtual standard document | The same validated standard-library URI resolves to the same pinned module. Moving the lookup earlier does not replace the module or admit overlays. |
| Exact disk standard source | `standardLibraryDocument` retains its filename plus exact-source match (`standard.go:41-55`). Workspace files with only a coincidentally matching name gain no new authority. |
| Ordinary module and symlink alias | The same `EvalSymlinks` and module-path matching logic remains in `analysis.go:71-79`. One canonical result now filters all occurrences. |
| Missing file / missing module | Failed symlink evaluation keeps the original path. If no module matches, the identity remains empty and ordinary nonempty-file occurrences remain filtered. |
| Incomplete/errored checked result | There is still no new Success requirement; existing recovered checked facts remain available. |

The lookup now happens before building the index rather than after it, but both helper paths use the immutable pinned standard registry and read the checked result. No result-changing mutation was found between the former and new evaluation points. The change creates no shared cache, goroutine, or new synchronization contract.

A filesystem symlink changed concurrently during one request could previously produce different identities for different occurrences. The new behavior uses one identity for the occurrence loop, consistent with request-level analysis. It still performs the existing second lookup for the expression pass; the patch does not claim a fully frozen filesystem identity across the whole request.

## Test coverage assessment

**The previous nonblocking assertion gap is resolved in the reviewed head.**

At `performance_test.go:58-65`, the imported `f_0_0` call is a function with checked analysis and is not a function under lexical fallback. This establishes that checked analysis contributes to the result. The imported call alone would not isolate the optimized loop, because both that loop and the later expression pass classify it.

The follow-up at `performance_test.go:67-79` opens `part_0.ms` using the same already checked four-module result and locates its first `value` parameter declaration. It asserts parameter kind 8 with checked analysis and a different kind under lexical fallback. `sourceIndex` adds this parameter through `program.Parameters()`; the indexed-occurrence pass recognizes its `parameter:` key. The later expression pass only emits type/function classes, and a declaration token is not a function/type declaration name. Thus removing or failing to match the first loop would fail this added assertion.

This is a focused and useful negative control. It also exercises filtering for an imported project module rather than only the manifest entry document. No further test-strengthening request remains for this small hoist.

Other fixture observations:

- The benchmark creates 40 imported modules with 20 checked exported functions each and verifies 41 project modules; this prevents silently benchmarking a failed or single-module fixture.
- The smaller test verifies four project modules and valid five-integer token groups.
- The symlink assertion compares the full token stream against the original URI while keeping the checked result fixed. This exercises the canonical-identity path relevant to the hoist.
- Platforms unable to create a symlink skip the test after the ordinary assertions have run. That limitation is explicit in the test.
- `semanticKindAt` correctly resets the relative character accumulator when a new line begins for valid LSP token groups.
- The fixture helper's zero-module/zero-function inputs would be invalid, but its two actual callers pass positive fixed values. No public API promise is implied.

## Measurement boundaries

`BenchmarkSemanticProject` at `performance_test.go:92-103` times repeated semantic-token generation from one already analyzed result. Fixture construction and analysis occur before `ResetTimer`; `ReportAllocs` is enabled; a global sink keeps the result observable. This is a suitable benchmark for the local optimization.

It does **not** measure fresh compilation, didChange analysis, complete LSP wire latency, VS Code behavior, first-use registry initialization, or different project shapes. The 40 imported modules and all pinned standard declarations intentionally amplify repeated module identity lookup. Before/after numbers should use this identical fixture, toolchain, host controls and repeat policy, and must be described as semantic-token generation results for this fixture.

The commit contains no numerical improvement claim to verify. I did not independently run its benchmark or tests. Parent-run exact-commit checks and CI remain required by the current delivery plan; this review cannot substitute for them.

## Verdict limits

No blocker was found in the exact reviewed head. Any later commit, combined future-stage patch, or base update needs review of its resulting diff; this approval does not carry forward automatically. Exact-head CI and parent-run measurement remain delivery gates outside this static review.

