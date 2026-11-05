[Wiki](../index.md) › [Tooling and docs](index.md)

# Teach a runnable path before formal reference

Decision: public documentation should focus on Manuscript and what readers can build. Remove comparisons with other languages, coverage maps, implementation inventories, and review bookkeeping. Keep one getting-started guide; modules, references, and cleanup belong in the language reference, application builds in developer tools, and compiler internals in contributor documentation. Use clear topic names and keep the sidebar, overview, and reading order consistent.

Decision: lead onboarding with a successful program and its benefits. Keep conditional tool downloads, cache behavior and local overrides together in the build guide; do not turn them into a universal Internet prerequisite in learning-page introductions. Keep consequential requirements accurate and reachable, and place troubleshooting beside the action it helps. Introduce review tools through a concrete task, such as exploring the offline HTML code map, rather than an implementation inventory.

Apply when: adding tutorials, revising design chapters, or explaining new syntax.
Evidence: the user’s November 5 correction of “an Internet connection for its first build” and request to feature HTML reports for human understanding; [learn index](../../documentation/learn/_index.md), [tool resolution](../../crates/ms-clif/src/link/lld.rs), [code map](../../documentation/developer-tooling/implementation.md#interactive-code-map).
Verify: run the displayed source and commands with the stated prerequisites; check that the reading path introduces dependencies before using them.

Decision: show concise, verified output beside practical commands and complete examples. State silent success accurately; use stable excerpts for variable reports and keep machine-specific paths, timings and IDs out of examples. Manuscript teaching examples are complete programs or tests with imports, explicit Result handling and visible ownership; do not publish unwrap shortcuts or incomplete replacement lines. Genuine declarations, schemas, output and tool commands retain their reference role. A learning page must teach a concrete task; remove generic advice that only repeats the tour or reference and redirect useful old routes.

Decision: audit public pages in navigation and prerequisite context, including generated library pages against their source comments. A page must help a reader perform or understand a concrete task; keep compiler stages in contributor material and exact contracts in their canonical reference. Record coverage and unexecuted platform checks outside the repository, not as user-facing review bookkeeping.

Decision: keep each teaching section to a short purpose sentence, a runnable example, its command and observed output, and at most two useful bullets. Prefer `T!` and `T?`, four spaces, and a related-page link; state alpha status where features are introduced. Keep runnable library examples, commands and expected outputs in `documentation/`, not in `stdlib/` source comments. API comments contain concise factual contracts and links to those examples. Audit every documentation fence and bounded tool view; never truncate a fenced example into an apparently runnable fragment.
