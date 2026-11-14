---
name: bug-bash
description: Probe one Manuscript area for real bugs, then fix them with regression tests and file issues for the rest. Use for "bug bash <area>" requests.
---

# Bug bash

Scope is one area (type checker, formatter, a stdlib module, a backend). Read [manuscript-change](../manuscript-change/SKILL.md) and the area's wiki checklist first.

1. **List open work.** Search open issues and PRs for the area so nothing is duplicated.
2. **Probe.** Write small `.ms` programs against current `main`, aimed at newer features and their boundaries (generics, interfaces, ownership, `?.`, `T!`, `Clonable`, `Closeable`, cancellation). Check `ms` output, diagnostics, formatter round-trips, and native execution. Compare against the documented rule, not against what the implementation happens to do.
3. **Triage each finding.** Wrong behavior or a misleading diagnostic: fix it. Design questions or large work: file an issue with [create-issue](../create-issue/SKILL.md), including the smallest repro. Do not guess at a language change; the user decides those.
4. **Fix with a regression test** at the layer that fails for the right reason ([wiki](../../wiki/testing-and-conformance/index.md)). A global change (for example how a type prints) can break frozen conformance fixtures: run `make conform` before pushing.
5. **Check correctness against references.** Compare results with published test vectors or a reference library (Python is fine for answers, never for timings) on both the Cranelift and LLVM backends. The same failure gives the same error kind on every platform (for example a missing program is ENOENT, a non-executable file EACCES).
6. **Fix classes, not instances.** When the same kind of bug recurs, ask what is missing architecturally (one general mechanism, a generated check) and fix it once instead of patching each site. A new module gets a hardening pass: fuzz its decoders and parsers and fix what breaks.
7. **Audit before you finish.** Read the round's merged PRs against the [root-cause rule](../../wiki/repository/fixes-address-the-root-cause-not-a-name-or-shape.md); file an issue for each special case or symptom patch and fix it properly.
8. **Land.** Combine related fixes into one PR with [create-pr](../create-pr/SKILL.md). Report what held up as well as what broke. Run rounds until one finds nothing new or major. When an area is clean, report it with a list of areas not yet covered so the next one can be assigned.
