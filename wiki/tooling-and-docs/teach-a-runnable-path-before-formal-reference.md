[Wiki](../index.md) › [Tooling and docs](index.md)

# Teach a runnable path before formal reference

Decision: public documentation should focus on Manuscript and what readers can build. Remove comparisons with other languages, coverage maps, implementation inventories, and review bookkeeping. Keep one getting-started guide; modules, references, and cleanup belong in the language reference, application builds in developer tools, and compiler internals in contributor documentation. Use clear topic names and keep the sidebar, overview, and reading order consistent.

Decision: lead onboarding with a successful program and its benefits. Keep conditional tool downloads, cache behavior and local overrides together in the build guide; do not turn them into a universal Internet prerequisite in learning-page introductions. Keep consequential requirements accurate and reachable, and place troubleshooting beside the action it helps. Introduce review tools through a concrete task, such as exploring the offline HTML code map, rather than an implementation inventory.

Apply when: adding tutorials, revising design chapters, or explaining new syntax.
Evidence: the user’s November 5 correction of “an Internet connection for its first build” and request to feature HTML reports for human understanding; [learn index](../../documentation/learn/_index.md), [tool resolution](../../crates/ms-clif/src/link/lld.rs), [code map](../../documentation/developer-tooling/implementation.md#interactive-code-map).
Verify: run the displayed source and commands with the stated prerequisites; check that the reading path introduces dependencies before using them.
