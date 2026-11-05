[Wiki](../index.md) › [Tooling and docs](index.md)

# Teach a runnable path before formal reference

Decision: public documentation should focus on Manuscript and what readers can build. Remove comparisons with other languages, coverage maps, implementation inventories, and review bookkeeping. Keep one getting-started guide; modules, references, and cleanup belong in the language reference, application builds in developer tools, and compiler internals in contributor documentation. Use clear topic names and keep the sidebar, overview, and reading order consistent.

Decision: lead onboarding with a successful program and its benefits. Keep conditional tool downloads, cache behavior and local overrides together in the build guide; do not turn them into a universal Internet prerequisite in learning-page introductions. Keep consequential requirements accurate and reachable, and place troubleshooting beside the action it helps. Introduce review tools through a concrete task, such as exploring the offline HTML code map, rather than an implementation inventory.

Apply when: adding tutorials, revising design chapters, or explaining new syntax.
Evidence: the user’s November 5 correction of “an Internet connection for its first build” and request to feature HTML reports for human understanding; [learn index](../../documentation/learn/_index.md), [tool resolution](../../crates/ms-clif/src/link/lld.rs), [code map](../../documentation/developer-tooling/implementation.md#interactive-code-map).
Verify: run the displayed source and commands with the stated prerequisites; check that the reading path introduces dependencies before using them.

Decision: show concise, verified output beside practical commands and complete examples. State silent success accurately; use stable excerpts for variable reports and keep machine-specific paths, timings and IDs out of examples. Fragments do not need invented output. A learning page must teach a concrete task; remove generic advice that only repeats the tour or reference and redirect useful old routes.

Decision: audit public pages in navigation and prerequisite context, including generated library pages against their source comments. A page must help a reader perform or understand a concrete task; keep compiler stages in contributor material and exact contracts in their canonical reference. Record coverage and unexecuted platform checks outside the repository, not as user-facing review bookkeeping.

Decision (November 5 documentation redo): teach writing, understanding, checking, running, testing, and shipping programs. Reviewing agent-written code is one workflow. Preserve explanations and exact rules while improving progression; a short page or passing isolated test does not replace a lesson. Use Swift's tour / explanatory guide / exact reference separation as pedagogical inspiration, without copying its text or feature inventory. Keep README and VISION unchanged for this redo, retain the site design and tagline, and create a fresh draft PR from current main. The user closed #2591 and explicitly withheld merge permission; do not reuse that patch, enable auto-merge, dispatch workflows, deploy, or merge this redo.

Verify: compare concept and anchor coverage to current main; run complete examples and displayed commands; report unexecuted checks honestly. Library recipes and runnable programs belong in authored documentation, not standard-library source or comments. This later direction supersedes the earlier all-library-prose ownership rule for tutorials.
