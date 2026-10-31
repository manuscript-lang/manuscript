# Repository guidance

Manuscript is a statically typed, natively compiled language implemented in Rust. Source `.ms` files are parsed and checked, then compiled to native executables.

## Start each session

- Read [the Manuscript vision](VISION.md) for design direction while respecting current technical contracts. The vision describes aspirations, not evidence of shipped features; verify current behavior against source, tests, and canonical guides.
- Read [architecture](documentation/contributing/architecture.md) and [development checks](documentation/contributing/development.md) for implementation or repository work. Check the relevant source and tests before assuming a documented design is implemented.
- Before implementing or reviewing a change, read [manuscript-change](skills/manuscript-change/SKILL.md), select relevant domain skills below, and read the [wiki](wiki/index.md) pages it routes to. Read additional skills if exploration reaches another domain; do not load the whole catalog for every task.
- Apply [language-design-taste](skills/language-design-taste/SKILL.md) for language, standard-library, runtime, compiler, or tooling design choices.
- The user's latest explicit direction and current canonical design take precedence over remembered preferences. Historical proposals and assistant completion reports do not establish current behavior. Identify material differences between a newer decision and this checkout.
- Read the [wiki](wiki/index.md) for the domains you touch before changing code. When a correction, user decision, or verified failure would change future work, update the wiki in the same change ([protocol](wiki/README.md), [record durable lessons](skills/manuscript-change/SKILL.md#record-durable-lessons)): edit the closest page, keep it short, and delete superseded advice.
- Find code and standard-library APIs with `ms search_symbol <name or words>` (project and standard library, fuzzy, bounded output) before reading files or guessing signatures; `ms search_symbol <module>` or `<module>.<Name>` shows a page. `ms guide` prints the language cheat sheet.

## Domain skills

| Task or affected surface | Read |
| --- | --- |
| Simplification, duplicated behavior, unnecessary work, or hard-to-follow layers | [simplify](skills/simplify/SKILL.md), then affected domain skills |
| Syntax, types, calls, imports, interfaces, language semantics | [language-design](skills/language-design/SKILL.md) |
| Syntax nodes, lexer/parser, checking, lowering, module resolution, build pins/cache, native toolchain | [compiler](skills/compiler/SKILL.md) |
| Execution, resources, cancellation, cleanup, native dispatch, standard declarations, bindings, API design | [runtime](skills/runtime/SKILL.md) |
| Formatter, lint, inspection, LSP, VS Code, CLI, profiling | [tooling](skills/tooling/SKILL.md) |
| Tutorials, exact rules, generated API reference, Hugo book/publication | [documentation](skills/documentation/SKILL.md) |
| Documentation revamps, marketing landing page, onboarding, reading order, or quality audits | [improve-documentation](skills/improve-documentation/SKILL.md), then documentation |
| Package organization, dependency policy, pins, CI, releases, repository cleanup | [repository-maintenance](skills/repository-maintenance/SKILL.md) |
| Writing or revising a design proposal | [author-proposal](skills/author-proposal/SKILL.md) |
| Opening or updating a pull request | [create-pr](skills/create-pr/SKILL.md) |
| Filing or rewriting an issue | [create-issue](skills/create-issue/SKILL.md) |

Syntax changes usually need language-design, compiler, tooling, and documentation. Standard API changes usually need runtime, tooling, and documentation. Select only domains the change reaches.

## Repository layout

- Manuscript is implemented in Rust in `crates/`, with Cranelift for debug builds and LLVM for Linux and macOS release builds; `crates/DESIGN.md` records the pipeline and ABI. Build it with `make build`, or `cargo xtask runtime` followed by `cargo build --release --locked -p ms-cli` (the build script embeds the runtime archive and panics without it); see the [Rust toolchain guide](documentation/contributing/rust-toolchain.md). The Go implementation was removed; its history is in git.
- Standard-library declarations live in `stdlib/` (`*.ms`) and are embedded by `crates/ms-check/build.rs`. Conformance fixtures live in `tests/conformance/`; `.msversion` holds the release version.
- Performance and agent evidence lives in `bench/perf/` and `bench/agent/`, each suite with its run script and a committed result page naming the revision and machine. A speed or agent claim in the README, website, or vision cites one of those pages; rerun the suite and add a dated section rather than editing old numbers.

## Shared guidance and checks

- Before any change that touches large parts of the codebase across multiple packages (for example a new representation, layer, or pass, or a restructure), write a short proposal in `proposals/` with [author-proposal](skills/author-proposal/SKILL.md) and validate it yourself before implementing: the problem, the concrete benefit with evidence (measurements, or code the change removes), and the alternatives, including doing nothing, after a pass on what can be simplified. Have an independent skeptical reviewer subagent challenge the evidence and the do-nothing case, and build only if the proposal survives. Do not implement first to find out whether it helps. Ask the user only when the change alters the language or user-visible behavior.
- Every PR, however it is opened (including by an agent harness that supplies its own body format): read [create-pr](skills/create-pr/SKILL.md) first, use the four-section body from `.github/pull_request_template.md` (Problem, Proposed change, Alternatives considered, Testing), open it ready for review, and enable squash auto-merge.
- Nested `match` is an anti-pattern. Keep implementation, examples, and diagnostic remedies flat: bind a payload with an early exit, use compatible `try`, or call a small helper. `make repo-check` guards source and Markdown fences; intentional syntax/semantic regressions need a scoped test allowance with a reason. The grammar remains unchanged. See [flat match flow](documentation/core-language/control-flow/pattern-matching.md#keep-match-flow-flat).
- Shared skills live in `skills/`; `.agents/skills/` and `.claude/skills/` link to the same folders for Codex and Claude discovery. Read selected `SKILL.md` files and relevant evidence links. Keep discovery links synchronized when adding, renaming, or removing skills.
- `AGENTS.md` is the sole source of repository guidance. `CLAUDE.md` contains only `@AGENTS.md` so Claude Code, which loads `CLAUDE.md` and not `AGENTS.md`, reads the same file; add no other content to it.
- Skills describe workflows, `wiki/` ([index](wiki/index.md)) preserves decisions, reasons, and failure modes for agents, and `documentation/` owns exact rules. All standard-library documentation belongs in `stdlib/*.ms`, including guide comment blocks; generate disposable book Markdown with `make docs`.
- Keep skills concise and specific to Manuscript. Do not reinstall generic collections during routine setup. [Skill maintenance and history](skills/README.md) records why this catalog exists.
- Run checks appropriate to the changed behavior from the current Makefile; Rust changes add `cargo fmt --all --check`, `cargo clippy --workspace --all-targets -- -D warnings`, and `cargo nextest run --workspace`. `make verify` is the routine gate; `make verify-full` adds the conformance corpus, every e2e fixture, book, and distribution checks. Guidance-only edits need reference/discovery validation and license freshness when notices change.
