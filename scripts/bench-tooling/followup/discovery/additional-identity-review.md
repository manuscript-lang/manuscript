# Skeptical decision: proposed generated closed-candidate grouping

**Decision: WITHHOLD canonical discovery from production. Do not implement the additional deduplication proposal.**

Reviewed `discovery-generated-scope-plan.md` against the earlier design/correctness matrix, actual current selection and overlay code, and exact b49/082 operation evidence. This records the parent's final decision and the independent reasoning supporting it. No source edit, test, benchmark or additional implementation was performed by this reviewer.

## Why doing nothing wins here

The valid eight-file probe saves 1–4 WalkDir callback visits and no discovery reads. The canonical rewrite creates additional lexical selected analysis contexts; whole probe elapsed grows from 3.37s to 11.48s, with no controlled latency-improvement evidence. Those elapsed values alone are not a benchmark, but adding more strict analyses is a concrete cost.

The proposed grouping would add another selected-context identity, overlay classification and filesystem-validation layer primarily to recover work introduced by the unpublished rewrite. It has no demonstrated independently valuable performance benefit over retaining baseline discovery. Per-file nearest-manifest checks can themselves exceed the callbacks saved. Establishing a safe new identity and measuring it would expand a task whose small measured benefit already argues against implementation.

The alias-only unopened-discovery omission is real and documented. Fixing it can be separate correctness work with explicit behavior/performance tradeoffs. It does not justify presenting this canonical rewrite as a performance optimization today.

## Equivalence obligations remain substantial

The short proposal correctly acknowledges these obligations; it does not prove them away:

- “Generated URI is absent from docs” is not a definition of closed input. A generated candidate can carry unique admitted text from an open alias. CLOSED must exclude all admitted actual ordinary open records for that physical identity, not just one spelling.
- Initial root equality is insufficient. Each rebased file can encounter a different lexical ancestor or nested manifest. Selection kind, canonical containing root, invalid-manifest behavior, configuration/aliases, standalone confinement and the selected source identity must agree per file.
- A symlinked manifest file must retain the containing directory's selection, not its target directory. Standalone symlink-file errors must not become success through physical-target grouping.
- Each actual URI, text, version and request-specific source override remains independent. Equal encoded filenames and divergent alias records cannot be collapsed through arbitrary map iteration or stale generated text.
- Ambiguous admitted overlays, failed canonicalization and validation errors must opt out conservatively. CanonicalOverlay failure cannot become empty overlays. Determining those conditions has its own filesystem/assembly cost.
- Skipping a generated strict analysis still needs a narrow explanation of which observable checked context is redundant. Shared bytes alone do not prove equivalent diagnostics or current filesystem state. Do not introduce a checked-graph memo or remove fresh rename validation to make this grouping pay.

These conditions are plausible boundaries for a separate future investigation, not proof supporting a production change now. No new counterexample implementation or extra identity abstraction is needed to make the present disposition concrete.

## Recorded outcome

- Exact `082c74274e437bf540ee6834f45c2ca835e5f7d6` retains scoped static correctness acceptance after its read-order correction; **publication remains HOLD**.
- The intermediate `fd6fe4567df02c943327a481739afb8a589906e3` remains a recorded failing read-error control and must not be published alone.
- Retain the immutable b49→082 source patch, final counts/probes, pin/hash metadata and negative controls as a research artifact. Label the actual savings and increased strict-analysis work; no end-to-end speedup claim.
- Owner watcher work should be extracted onto clean b49 with only its minimal pathWithin helper. No workspace/discovery production source from this experiment is required. It needs its own exact-head review, measurements and CI.
- No additional canonical grouping implementation is authorized. Reopening it would need a separate concrete user-visible objective or a materially stronger measured do-nothing comparison, plus the full equivalence obligations above.

