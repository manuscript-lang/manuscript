# Merged tooling replay, 2026-10-31

All four production PRs merged normally: [#2095](https://github.com/manuscript-lang/manuscript/pull/2095), [#2109](https://github.com/manuscript-lang/manuscript/pull/2109), [#2123](https://github.com/manuscript-lang/manuscript/pull/2123), [#2137](https://github.com/manuscript-lang/manuscript/pull/2137). Evidence #2141 also merged. This new pass pins actual combined main `6e37717ed3b4035af48cafb50f92272e9fa042c9`, tree `d958d00a06a8e9dda054355b10be3888bf104234`. Main advanced later; these results apply to this pin.

## Matched producers and checks

The counterfactual tree is `6a37bedb7f05a91c7dc8933d82f5582ef15b403b`: reverse only the four own production patches in `nav.rs`, `text.rs`, `semantic.rs`, `symbols.rs`, and syntax `format.rs`. Later navigation ordering, complete-scalar scanning and formatter spacing fixes remain. Independent review verified the exact five-file reversal. Standard declarations, dependencies, resolved registry versions/checksums, harness sources, physical source path and compiler flags match. [Provenance](provenance.json), [reversal](counterfactual.patch), and [binary hashes](binaries.sha256) preserve identities.

Pinned Rust/Cargo 1.99.1, rustc `58cf8f9c3` (2026-10-13); Linux 6.18.57 x86_64, AMD EPYC 9V45, five allowed CPUs, approximately 17 GiB RAM. Release opt-level 3, debug 1, panic abort, no custom flags/LTO/CPU tuning. Cargo setup/builds are excluded, with separate before/after target directories. No native Manuscript compiler or installed editor client is involved. These are tooling implementation comparisons, not generated-language Rust parity; no equivalent external formatter/LSP contract was established.

`cargo test --locked -p ms-syntax -p ms-lsp -p ms-tooling` passes 182 tests on actual main and 181 on the counterfactual, zero failures/ignored. The difference is the optimized helper's own unit test. Focused all-targets Clippy with warnings denied and workspace Rust formatting pass. Unrelated archive bodies are omitted in this local snapshot; required scoped source/fixtures are complete. This is not a full repository-invariant, native conformance, workspace or Windows validation. #2150 was still unmerged when commands were selected from actual main.

All **4,480 measured invocations** passed strict declared output identities/source sizes: navigation 920, semantic 1,360, outline 1,020, formatter 1,180. Ten balanced AB/BA fresh-process samples per binary/case, CPU 0, untimed warmups, no concurrent intentional builds/tests during timing. No sample removed. Setup is excluded except completion's request analysis; full JSON/formatter output is consumed. Hover/index fingerprints cover selected declared facts, not every analysis field. Formatter idempotence is checked outside measurement. VmHWM includes setup; no isolated allocation or instruction evidence is claimed. Host exclusivity is not claimed.

| Workload | Before ms | Merged ms |
| --- | ---: | ---: |
| Literal hover, 1,000 functions | 41.5515 | 0.1144 |
| References, 1,000 results | 8.0921 | 0.9624 |
| Semantic, 8,192 flat items | 159.4405 | 2.0578 |
| Outline, 1,000 symbols + 1 MB suffix | 409.9543 | 3.5302 |
| Format, 2,048 implicit steps | 2475.4714 | 4.2856 |
| Format, 2,048 explicit steps | 60.0079 | 4.7421 |

## Every median more than 3% slower

This cutoff is for display, not acceptance. Every smaller change remains in raw CSVs and [analysis distributions](analysis.json); ranges are not confidence intervals. Unchanged source paths do not prove absence of regression or establish its cause. Costs remain unresolved observations; no blanket regression-free claim is supported.

| Suite/case | Before μs | After μs | Delta μs | Change | Before min–max μs | After min–max μs |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| navigation/hover/1/ascii | 5.671 | 5.861 | 0.190 | 3.36% | 5.472–7.217 | 5.533–6.128 |
| navigation/hover-name/1000/ascii | 20.092 | 21.096 | 1.004 | 4.99% | 19.774–21.219 | 20.505–22.909 |
| semantic/hover-name/1000/ascii | 20.471 | 21.183 | 0.712 | 3.48% | 19.585–21.132 | 19.842–21.881 |
| semantic/index/100/ascii | 4709.518 | 4882.139 | 172.621 | 3.67% | 4619.540–4818.734 | 4623.193–5881.013 |
| formatter/512/list-lines | 417.953 | 436.815 | 18.862 | 4.51% | 416.232–423.616 | 430.234–442.587 |
| formatter/8192/list-lines | 6722.981 | 6947.003 | 224.022 | 3.33% | 6641.229–7073.651 | 6786.435–7243.270 |

## Fresh discovery and remaining work

Forty [larger-flow observations](larger-flows.csv) cover 128/512/2,048/4,096 accepted steps, implicit/explicit, five each. Implicit medians 0.274/1.038/4.177/7.954 ms and pipe 0.326/1.192/4.701/9.322 ms remain approximately linear. No new actionable issue appeared in those accepted shallow shapes. The known 8,192 implicit-flow parser-limit rejection was not retried or bypassed.

Sixty [workspace observations](workspace.csv) cover 1/4/16/64 independent modules, all/target/missing queries, five each. All-result medians 10.0/26.8/84.1/321.5 ms; target 5.6–6.2 ms; misses 25–464 μs. Every fixture file exists before first analysis. Counts/full-rendered fingerprints remain stable. This is ordinary query coverage, not a cache invalidation, shared-import, cold filesystem, overlay or cancellation study.

A fresh static review identified separate unmeasured shapes, then [95 discovery observations](new-candidates.csv) tested broad empty-prefix completion, documentation-heavy completion, nested formatter calls and long-head chains with nontrivial arguments. Full outputs/counts/sizes are consumed and five samples per case are stable. Broad completion at 2,048 declarations takes about 162 ms, documentation-heavy completion 857 ms; 2,048 large-argument chain steps take 66.6 ms. These motivate focused follow-up experiments: cache the identical completion edit range, and avoid repeated call-prefix width scans. They are not included in the four-fix replay above. Nesting depth 128 takes 1.01 ms; output indentation itself grows with depth, so no avoidable-complexity claim follows without normalization.

The initial discovery fixture omitted the required function result type. It failed before formatter timing. Forty earlier completion observations are retained [separately](rejected-invalid-result.csv) and excluded from usable evidence; the corrected complete candidate pass is the 95 rows above. The probe build initially used a private item field; corrected to the public JSON interface before timing. Neither is a product bug.

No lane-wide clean claim: the new candidates require measured follow-through. Broad member/argument completion, many modules with long documentation, alternating-module reference performance, deeper accepted nesting, large shared-import workspaces, many overlays, cancellation and cold filesystem behavior remain untested. Backend/codegen/lowering, language ownership/cleanup/lifetimes, native parity/cache, Windows, Debug JSON and HTTP/network investigations remain outside this lane. Previous native CI failures remain undiagnosed; fresh successful CI and #2139 integration do not establish their cause.

## Reproduction

Use the immutable four harnesses under `bench/perf/{lsp,lsp-semantic,lsp-outline,formatter-flow}` at the pinned commit (or its immutable Git blob links if later removed). Copy ordinary source/fixtures/manifests outside the checkout, adapt only local dependency paths, resolve locks using the pinned main registry versions, and build both source states in the same physical checkout using separate target directories. Keep identical resolved locks and harness bytes. Do not restore removed finished directories merely to undo later repository cleanup.

Run each original `compare.py` with ten samples; navigation is launched through `taskset --cpu-list 0`, and semantic/outline/formatter pass `--cpu 0`. `analyze.py` checks every identity/order/sample and recomputes distributions (adjust its artifact prefix when running from this report directory). `run-discovery.py` and `probes/` preserve the later independent-module and candidate workload sources. Local paths in manifests/commands are provenance and require adaptation; do not treat them as installed-client commands.
