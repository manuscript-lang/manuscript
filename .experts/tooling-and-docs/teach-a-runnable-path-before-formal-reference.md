[Wiki](../index.md) › [Tooling and docs](index.md)

# Teach a runnable path before formal reference

Decision: public documentation should focus on Manuscript and what readers can build. Remove comparisons with other languages, coverage maps, implementation inventories, and review bookkeeping. Keep one getting-started guide; modules, references, and cleanup belong in the language reference, application builds in developer tools, and compiler internals in contributor documentation. Use clear topic names and keep the sidebar, overview, and reading order consistent. Teach basics, functions, types, control flow, errors, modules, and resource management before library services. Library topics should be directly reachable. State availability and limits beside the affected feature. Use practical, example-first progression through variables, collections, functions, types, errors, and modules; keep indexes short and link to exact rules. Clearly separate intentional rejection examples from the usual runnable path.

Apply when: adding tutorials, revising design chapters, or explaining new syntax.
Evidence: [learn index](../../documentation/learn/_index.md).
Verify: run the displayed source and commands with the stated prerequisites; check that the reading path introduces dependencies before using them. Sidebar and previous/next links use the same [navigation order](../../website/data/navigation.toml); the [publication checks](../../tests/docs/publication.test.cjs) compare their rendered order. Build the book with its current strict checks and link to canonical rules instead of repeating them.

Verified: task recipes must preserve I/O failure: matching a failed stdout write and returning success hides an undelivered result. [Common tasks](../../documentation/learn/common-tasks.md) forwards write/flush errors to a nonzero entry status. Type checking alone cannot establish the displayed output, EOF handling, or failure status; a complete example needs an executed check, and the docs and examples categories of the [conformance corpus](../../tests/conformance/README.md) are where fences are run.

---
Topics: [Documentation](../topics/documentation.md)
