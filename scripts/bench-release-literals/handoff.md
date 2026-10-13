# #147 handoff and consolidation observations

The bounded Release assessment is complete; publishing/review of its evidence
is the only active step. Debug #272 is merged as35b849a3, with green exact-head
full CI/all12 distributions and copied-binary postmerge DAP/ordinary-output
verification. Do not reopen or rerun that completed work.

#238 remains held: both its eager boxed table copy and this root-free factory
sweep regress normal-GC construction. #147 stays open. The next technical seam
depends on #271's published/reviewed checked numeric mapping and #142's single
authoritative typed List storage, with an allocation-neutral fresh constructor.
The synthetic embedded-owner control has two allocations and promising numeric
copy costs, but establishes neither future default32 semantics nor production
ABI/source/native parity. No Release production patch is proposed for merge.
Keep #278 then #266 shared-file ordering; this branch changes neither.

Under the user's consolidation-first direction, stop after this evidence handoff.
No additional residual slice, broad refactor, skill rewrite or storage cutover is
started here. The observations below are grounded in the current paths, not a
mandate to rearrange packages before checking their observable contracts.

- **Storage ownership crosses layers.** `pkg/compiler/lower_expressions.go`
  constructs `List{Type,Items}` directly; `pkg/compiler/lower_collections.go`
  emits selected direct operations; `pkg/runtime/collections.go` supplies those
  paths and bound/native dispatch with direct Items access. Generic iteration,
  formatting, equality and constructors also live in `pkg/runtime/values.go`.
  A coherent storage-access layer is a prerequisite for typed cutover; optimizing
  one literal constructor cannot preserve aliases if the remaining writers still
  mutate an independent exported slice header or mirror.
- **Large-module pressure is specific.** On basec80bdb2a,
  `pkg/runtime/values.go` is1309 lines and owns representation headers, invocation,
  defaults/generics, records/alternatives, iteration, formatting and equality.
  `pkg/compiler/cache.go` is426 lines combining pins, artifact/cache identity,
  publishing and selected native builds. Those are candidate responsibility
  boundaries for later consolidation, not reasons to split by line count alone.
- **Benchmark orchestration is duplicated/tightly coupled.** The held #238
  `scripts/bench-flat-literals/` and shipped `scripts/bench-debug-literals/` each
  have source generation/build/runtime orchestration; this new Release emitter
  again locates generated constructor text. Its memory runner imports HARNESS
  from a folder named Debug, although instrumentation is build-kind neutral.
  A later shared benchmark layer should separate checked workload emission,
  immutable baseline/provenance, artifact construction and paired measurement.
  It must preserve historical hashes and label synthetic controls explicitly.
- **Expert routing overlaps verified domains.** `skills/compiler/SKILL.md`,
  `skills/runtime/SKILL.md` and `skills/tooling/SKILL.md` all address lowering,
  observable contracts, source maps/native execution and standalone checks;
  `skills/manuscript-change/SKILL.md` repeats the shared trace/evidence workflow.
  `.experts/tooling-and-docs.md` is313 lines mixing build/performance/debugger
  lessons with documentation/editor workflows, while `.experts/language.md`
  and `.experts/runtime.md` also cover relevant evaluation/alias contracts.
  Keep AGENTS.md as the sole entrypoint; retain one common workflow and concise
  domain-specific obligations, with exact rules in canonical documentation and
  experiments linked as evidence. Preserve distinctions between accepted design,
  measured mechanism and still-held proposals.
