# Matched tooling performance preflight — 2026-10-31

**Later evidence:** all four source PRs and #2141 merged. The [actual combined-main replay](final-main-6e37717e/README.md) validates 4,480 samples at `6e37717e`, preserves six slower controls and records new discovery candidates. The historical checkpoint below remains unchanged.

Maintenance note: the failure status below records the original published heads. Subsequent routine maintenance integrates actual main `81b804d58131224a00a10ebe3f3824e6c84313e1`, including #2139, without diagnosing the earlier failures. Formatter head `15b318784dfff57fa8802c2ac67bde3c0add231d` passes 181 focused tooling tests, clippy and Rust formatting. Fresh normal CI is tracked on the PRs; no prior-failure cause or final merged-main completion is claimed. Historical measurements and slower controls below are unchanged.

**This is preflight evidence, not completed merged-main validation.** The three LSP PRs [#2095](https://github.com/manuscript-lang/manuscript/pull/2095), [#2109](https://github.com/manuscript-lang/manuscript/pull/2109) and [#2123](https://github.com/manuscript-lang/manuscript/pull/2123) merged normally. Formatter PR [#2137](https://github.com/manuscript-lang/manuscript/pull/2137) is published with auto-merge enabled; required CI has failed: [run 41230780663](https://github.com/manuscript-lang/manuscript/actions/runs/41230780663), job 124626059261, step 17 **Conformance corpus (LLVM)**. Additional native failures are amd64 Cranelift corpus (job 124626059264, step 19) and arm64 LLVM corpus (job 124626059297, step 17). Only status metadata was read. Its cause and relationship to the formatter patch remain unknown; backend/parity investigation is outside this lane's standing campaign permission boundary. No rerun, bypass or manual merge was attempted. Actual combined-main replay remains blocked.

## Equivalent source worlds

Common main is `b69559b829304ab80d6267c3d4271807f36ceec2`. The candidate combines it with formatter head `18f496c85fb779ebcc3cbb409be3557a92b772a1`, producing tree `016e27a29492c91a79729de879edfc79276f18e4`. The counterfactual baseline reverses only this lane's three merged LSP production changes from that same main; its formatter predates #2137. Baseline tree: `c4d2b56cd2d9cc7547fd71ae5ecc251a73f3336e`.

Independent review verified that only the five intended production files differ: `nav.rs`, `text.rs`, `semantic.rs`, `symbols.rs`, and `ms-syntax/src/format.rs`. Standard-library sources, dependencies/lockfile and pinned toolchain are identical. Correctness #2065/#2070/#2075 and the existing formatter comment-indentation condition remain present. The new forward-coordinate helper and its own unit test are removed only from the counterfactual. Baseline passes 179 affected tests; candidate passes 181, clippy with warnings denied, Rust formatting and repository invariants. No local full native/workspace/conformance execution was substituted for required CI under the campaign's denied scopes.

An earlier old-main comparison stopped at an index fingerprint mismatch. Its 380 rows are retained separately under `rejected/`, and are not valid final comparative evidence. The mismatch establishes an output difference, not its exact cause. Reconstructing a same-main baseline restored matching index identities without filtering facts or weakening assertions. Historical isolated and earlier same-base reports remain unchanged in their original suite directories.

## Protocol and observations

All **4,480 measured invocations** passed declared workload fingerprint/source-size checks: navigation 920, semantic 1,360, outline 1,020, formatter 1,180. Every suite used ten balanced AB/BA fresh-process observations per producer/workload, CPU 0, identical release settings and Rust/Cargo 1.99.1 (`58cf8f9c3 2026-10-13`). Host: Linux 6.18.57 x86_64, AMD EPYC 9V45, five allowed CPUs, approximately 17 GiB RAM. No simultaneous builds/tests or other intentional CPU-intensive jobs ran during timing; host exclusivity is not claimed.

Each LSP producer warms one query; the formatter producer performs two untimed formatting calls, including output-idempotence verification. Generation/checking/index setup is outside timing, except completion's request analysis. JSON workloads consume complete rendered JSON; hover consumes selected offset/text; index consumes selected ordered identity/name/file/range facts; formatter consumes complete output. Timer details are in each original suite's README. Linux child VmHWM includes setup and does not isolate query allocations; no allocator/instruction counters were available.

Every raw sample and rounded summary is retained in the four CSV/summary pairs. [Provenance](provenance.json) records trees, reversal commits, binary/harness/data SHA-256 values and the CI blocker. All data CSV record endings are normalized to repository LF without changing records.

| Workload | Before ms | Combined after ms |
| --- | ---: | ---: |
| Literal hover, 1,000 functions | 41.5409 | 0.1126 |
| References, 1,000 same-file results | 8.0995 | 0.9474 |
| Semantic tokens, 8,192 flat-list items | 161.2003 | 2.0646 |
| Outline, 1,000 symbols + 1 MB whitespace | 479.1238 | 3.5285 |
| Format, 2,048 implicit flow steps | 2462.3019 | 4.1796 |
| Format, 2,048 explicit pipe steps | 60.0404 | 4.6810 |

These measure the Rust tooling implementation against its prior implementation, not generated-language Rust parity. No equivalent external formatter/LSP parsing/recovery/output contract was established. Six repeated-scan problems were addressed across the four source PRs; no universal language-server improvement follows.

## Costs, distributions and limits

All medians more than 3% slower in this pass are listed below. This is a display cutoff, not a regression-acceptance threshold. All other cases remain in the raw CSV and summaries. Tiny relative costs and larger absolute costs are separated; unchanged source paths do not prove absence of regression or establish a cause.

| Suite/case | Before μs | After μs | Difference μs | Change |
| --- | ---: | ---: | ---: | ---: |
| navigation/hover-first/1/ascii | 6.216 | 7.131 | 0.914 | 14.71% |
| navigation/hover-blank/1/ascii | 5.841 | 6.950 | 1.110 | 19.00% |
| navigation/hover-name/1000/ascii | 20.163 | 21.222 | 1.058 | 5.25% |
| navigation/hover-name/4000/ascii | 76.637 | 80.831 | 4.194 | 5.47% |
| semantic/semantic/1/list-flat | 7.515 | 7.881 | 0.366 | 4.87% |
| semantic/index/1000/ascii | 6433.782 | 6720.523 | 286.740 | 4.46% |
| formatter/format/512/list-lines | 414.604 | 427.755 | 13.151 | 3.17% |

Index construction at 1,000 functions is about 0.287 ms slower in one suite; it must not be grouped only with tiny hover costs. Indexed-name absolute differences also grow with workload size. Independent review found no demonstrated new source-level defect or supported speculative threshold/layout tuning. Normal final-main replay is still needed; unresolved costs must remain visible.

Selected min–max ranges across ten observations are below. They are not confidence intervals. Balanced ordering reduces directional drift but does not remove host noise, random per-process effects or binary differences. No samples were removed.

| Suite/case | Before range μs | After range μs | Before/after median RSS KiB |
| --- | ---: | ---: | ---: |
| navigation/hover-blank/1/ascii | 5.321–7.466 | 5.278–7.955 | 34648/34714 |
| navigation/hover-name/4000/ascii | 75.458–86.654 | 78.354–88.088 | 66776/66778 |
| semantic/index/1000/ascii | 6279.552–7252.756 | 6342.912–7414.429 | 46248/46186 |
| formatter/format/2048/flow | 2413417.474–2706033.927 | 4153.286–4218.640 | 6414/6454 |
| formatter/format/512/list-lines | 413.058–418.421 | 426.444–436.797 | 2336/2336 |

## Bounded fresh discovery

The larger-flow CSV has 40 observations: 128/512/2,048/4,096 steps, implicit/explicit flows, five samples each on CPU 0. Implicit-flow medians 0.280/1.065/4.324/7.962 ms and explicit-pipe medians 0.321/1.207/4.772/9.518 ms support approximately linear growth over accepted inputs. An 8,192-step implicit flow was rejected before timing by the existing 10,000-operator/access parser limit; that guard was not changed and no performance claim is made for the rejected input.

The workspace CSV repeats 60 ordinary independent-module observations: 1/4/16/64 modules, all/target/missing queries, five samples each. All-result medians 10.5/25.0/84.0/323 ms; one target 5.9–6.4 ms; misses 25–464 μs. Counts/fingerprints are stable. No new actionable scaling issue was demonstrated in these bounded shapes. Shared imports, large workspaces/files, many overlays, cancellation and cold filesystem behavior remain untested. No global clean claim is made.

Independent skeptical review verified all four matrices, distributions, strict identities, baseline construction, fresh discovery and production merges. It did not investigate the native CI failure or submit a GitHub approval. Final merged-main performance/correctness completion remains pending that blocker.

## Reconstruct the comparison

Create two isolated worktrees at the common main, then merge only the formatter candidate into the after tree. The original three production reversals can be reconstructed from the immutable commits (also recorded in provenance.json):

```sh
git worktree add --detach .artifacts/tooling-before b69559b829304ab80d6267c3d4271807f36ceec2
git worktree add --detach .artifacts/tooling-after b69559b829304ab80d6267c3d4271807f36ceec2
git -C .artifacts/tooling-after merge --no-commit --no-ff 18f496c85fb779ebcc3cbb409be3557a92b772a1
git diff 9cf35d574845cb07c8af52ee4d0e5a0d1154ae0f^ 9cf35d574845cb07c8af52ee4d0e5a0d1154ae0f -- crates/ms-lsp/src/nav.rs > .artifacts/tooling-production.patch
git diff cb11524bbbfe27c7aba81b2320207fafe07ebd48^ cb11524bbbfe27c7aba81b2320207fafe07ebd48 -- crates/ms-lsp/src/text.rs crates/ms-lsp/src/semantic.rs >> .artifacts/tooling-production.patch
git diff b69559b829304ab80d6267c3d4271807f36ceec2^ b69559b829304ab80d6267c3d4271807f36ceec2 -- crates/ms-lsp/src/symbols.rs >> .artifacts/tooling-production.patch
git -C .artifacts/tooling-before apply --reverse ../../.artifacts/tooling-production.patch
cp -R .artifacts/tooling-after/bench/perf/formatter-flow .artifacts/tooling-before/bench/perf/
```

Build each standalone harness from its own worktree with pinned Rust 1.99.1, identical release settings and separate target directories. Use each suite's compare.py with ten samples. Pin navigation's entire comparator process with taskset (children inherit affinity); the other three accept `--cpu 0`. Preserve every raw observation and all strict output checks. The same procedure must be repeated on the actual merged main after #2137's required CI is resolved, retaining the newer source world in both producers.
