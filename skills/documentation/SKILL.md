---
name: documentation
description: Write, revamp, or audit Manuscript documentation: tutorials, canonical rules, generated references, contributor guides, landing page, and Hugo book, with runnable examples and publication checks.
---

# Documentation

Use for `README.md`, `documentation/`, `crates/ms-tooling/src/guide/`, or `website/`. Read [development/publishing](../../documentation/contributing/development.md), [source ownership](../../documentation/contributing/architecture.md#keep-source-and-generated-output-distinct), and [lessons](../../wiki/tooling-and-docs/index.md).

- Start with the reader's task. Explain one concept at a time in plain language with a small example; describe Equal/Hashable through comparison, lookup, and deduplication. Introduce dependencies before use.
- Keep only simple, focused examples and alternatives. Avoid contrived domain models, error hierarchies, and helper layers added just to make an example work. Keep control flow shallow; simplify the scenario instead of spreading deep nesting across more helpers. See the [example simplicity lesson](../../wiki/language/error-translation-does-not-need-a-dedicated-standard-helper.md).
- Keep docs minimal and let code be the source of truth: state what the checkout ships, trim restated prose, and label pending design as pending. Write only about Manuscript: no Node.js, JavaScript, or Go parity or comparison pages, and no language-comparison inventories.
- Give exact rules one canonical home and link there. Tutorials teach use and references define contracts. State limits on the relevant page; do not maintain separate coverage maps or language-comparison inventories.
- Check behavior/signatures against current source. Newer direction can supersede older guides; label pending design as pending rather than shipped.
- Complete tutorial fences use existing `manuscript-example` JSON annotations for run/test expectations. Confirm its directory is included in example discovery; annotations alone do not register other guides. Exercise displayed commands with stated prerequisites; label fragments. Do not duplicate complete examples in fixtures.
- Edit declarations/generators for generated APIs. Special contextual calls live in `stdlib/intrinsics.ms`; `make docs` (the `ms-docgen` binary in `crates/ms-tooling/src/guide`) generates ignored guides/references/call rules/downloads in `.artifacts/docs/` and `website/static/`. Never repair generated HTML/catalogs by hand.
- Language and contributor guides live in `documentation/`; standard-library guides live in documentation comment blocks in `stdlib/*.ms`, Hugo inputs/overrides in `website/`, generated HTML in ignored `.artifacts/book/`. Customize project overrides rather than vendored theme; `.msversion` is the shared version source.
- Run applicable example checks, `make docs-check` (validates source without requiring generated Markdown), and `make book-check`; `make book` generates production output with destination cleanup. Check project-prefix links, rendered signatures/downloads, highlighting, retired routes, and search artifacts after removal.
- When publishing is requested, verify actual Pages deployment and current reader artifacts separately from source freshness or merge success.

## Broad refresh or revamp

For a docs revamp, onboarding, reading order, or landing page, read [VISION.md](../../VISION.md) for positioning. Name the reader's task, the obstacle, and the observable result that removes it. Improve through structure, examples, and deletion as well as prose.

1. **Establish what ships.** Compare with current `main`; use `ms guide`, `ms search_symbol`, source, and tests as evidence (a vision is not proof). Trace changed concepts through the README, tutorials, rules, library comments, CLI help, and agent cheat sheet; searching an old spelling misses stale explanations. Check incoming links before deleting records.
2. **Audit the journey.** Read homepage, hub, quickstart, tour, recipes, and indexes in order, with [navigation](../../website/data/navigation.toml), titles, weights, and previous/next links. Learning, building, and reference are distinct intents; keep one reading order everywhere and preserve useful routes with redirects.
3. **Homepage.** A focused hero: headline, short description, primary trial action, secondary tour link, and a compact runnable program with its actual output. Claims about speed or adoption need evidence; mark aspirations. Work in project-owned Hugo overrides.
4. **Teach a finishable path.** First successful run before manifest internals; state directories, prerequisites, and platform differences; confirm the installed release supports the syntax shown. Trim filler and bookkeeping from reader pages.
5. **Verify the experience.** Run displayed commands in disposable directories, then `make docs-check`, `make repo-check`, `make book-check` (`make book` for production). Extend the [publication checks](../../tests/docs/publication.test.cjs) for new navigation contracts. Inspect desktop and mobile renders in light and dark themes; a successful HTML build does not establish visual quality. Recheck against latest `main`, and search rendered output for retired terms after removals.
6. **Report** the obstacles removed with evidence, never claimed conversion gains, and distinguish local changes, a merged PR, and a deployed site.
