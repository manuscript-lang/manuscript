---
name: documentation
description: Write Manuscript tutorials, canonical rules, generated API references, contributor guides, or Hugo book content with runnable examples and publication checks.
---

# Documentation

Use for `README.md`, `documentation/`, `pkg/tooling/docgen/`, `scripts/docgen/`, or `website/`. Read [development/publishing](../../documentation/contributing/development.md), [source ownership](../../documentation/contributing/architecture.md#keep-source-and-generated-output-distinct), and [lessons](../../.experts/tooling-and-docs.md).

- Start with the reader's task. Explain one concept at a time in plain language with a small example; describe Equal/Hashable through comparison, lookup, and deduplication. Introduce dependencies before use.
- Keep only simple, focused examples and alternatives. Avoid contrived domain models, error hierarchies, and helper layers added just to make an example work. Keep control flow shallow; simplify the scenario instead of spreading deep nesting across more helpers. See the [example simplicity lesson](../../.experts/language.md#error-translation-does-not-need-a-dedicated-standard-helper).
- Give exact rules one canonical home and link there. Tutorials teach use and references define contracts. State limits on the relevant page; do not maintain separate coverage maps or language-comparison inventories.
- Check behavior/signatures against current source. Newer direction can supersede older guides; label pending design as pending rather than shipped.
- Complete tutorial fences use existing `manuscript-example` JSON annotations for run/test expectations. Exercise displayed commands with stated prerequisites; label fragments. Do not duplicate complete examples in fixtures.
- Edit declarations/generators for generated APIs. Special contextual calls live in `pkg/tooling/docgen/call-rules.md`; `make docs` regenerates references/call rules/downloads. Never repair generated HTML/catalogs by hand.
- Guides live in `documentation/`, Hugo inputs/overrides in `website/`, generated HTML in ignored `.artifacts/book/`. Customize project overrides rather than vendored theme; `.msversion` is the shared version source.
- Run applicable example checks, `make docs-check`, and `make book-check`; `make book` generates production output with destination cleanup. Check project-prefix links, rendered signatures/downloads, highlighting, retired routes, and search artifacts after removal.
- When publishing is requested, verify actual Pages deployment and current reader artifacts separately from source freshness or merge success.
