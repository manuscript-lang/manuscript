# Repository guidance

Manuscript is a statically typed language implemented in Go. Source `.ms` files are parsed and checked, then lowered to Go for native execution.

## Start each session

- Read [the Manuscript vision](VISION.md) for design direction while respecting current technical contracts. The vision describes aspirations, not evidence of shipped features; verify current behavior against source, tests, and canonical guides.
- Read [architecture](documentation/contributing/architecture.md) and [development checks](documentation/contributing/development.md) for implementation or repository work. Check the relevant source and tests before assuming a documented design is implemented.
- Before implementing or reviewing a change, read [manuscript-change](skills/manuscript-change/SKILL.md), select relevant domain skills below, and consult the experts it routes to. Read additional skills if exploration reaches another domain; do not load the whole catalog for every task.
- Apply [language-design-taste](skills/language-design-taste/SKILL.md) for language, standard-library, runtime, compiler, or tooling design choices.
- The user's latest explicit direction and current canonical design take precedence over remembered preferences. Historical proposals and assistant completion reports do not establish current behavior. Identify material differences between a newer decision and this checkout.
- Use [manuscript-change](skills/manuscript-change/SKILL.md#record-durable-lessons) when a correction or verified lesson would change future work. Update existing entries rather than accumulating duplicate or superseded advice.

## Domain skills

| Task or affected surface | Read |
| --- | --- |
| Syntax, types, calls, imports, interfaces, language semantics | [language-design](skills/language-design/SKILL.md) |
| Syntax nodes, lexer/parser, checking, lowering, module resolution, build pins/cache, native toolchain | [compiler](skills/compiler/SKILL.md) |
| Execution, resources, cancellation, cleanup, concurrency, native dispatch, standard declarations, bindings, API parity | [runtime](skills/runtime/SKILL.md) |
| Formatter, lint, inspection, LSP, VS Code, CLI, debugger | [tooling](skills/tooling/SKILL.md) |
| Tutorials, exact rules, generated API reference, Hugo book/publication | [documentation](skills/documentation/SKILL.md) |
| Package organization, dependency policy, pins, CI, releases, repository cleanup | [repository-maintenance](skills/repository-maintenance/SKILL.md) |
| Opening or updating a pull request | [create-pr](skills/create-pr/SKILL.md) |
| Filing or rewriting an issue | [create-issue](skills/create-issue/SKILL.md) |

Syntax changes usually need language-design, compiler, tooling, and documentation. Standard API changes usually need runtime, tooling, and documentation. Select only domains the change reaches.

## Repository layout

- Reusable Go packages live in `pkg/`; executable entrypoints live in `cmd/`, and private CLI/native helpers live in `internal/`.
- Keep root Go embed carriers beside `go.mod`, `vendor/`, `.msversion`, and the generated toolchain payload. Package moves update imports, fixtures, dependency policy, release inputs, and expert routes; see the architecture guide.

## Shared guidance and checks

- Nested `match` is an anti-pattern. Keep implementation, examples, and diagnostic remedies flat: bind a payload with an early exit, use compatible `try`, or call a small helper. `make repo-check` guards source, Markdown fences, and Go source strings; intentional syntax/semantic regressions need a scoped test allowance with a reason. The grammar remains unchanged. See [flat match flow](documentation/core-language/control-flow/pattern-matching.md#keep-match-flow-flat).
- Shared skills live in `skills/`; `.agents/skills/` and `.claude/skills/` link to the same folders for Codex and Claude discovery. Read selected `SKILL.md` files and relevant evidence links. Keep discovery links synchronized when adding, renaming, or removing skills.
- Use this `AGENTS.md` as the sole repository guidance entry point; do not create a separate `CLAUDE.md`.
- Skills describe workflows, `.experts/` preserves reasons and failure modes, and `documentation/` owns exact rules. Standard signatures belong in `pkg/stdlib/*.ms`; regenerate derived references with `make docs`.
- Keep skills concise and specific to Manuscript. Do not reinstall generic collections during routine setup. [Skill maintenance and history](skills/README.md) records why this catalog exists.
- Run checks appropriate to the changed behavior from the current Makefile. `make verify` is the routine gate; `make verify-full` adds native, race, fuzz, book, and distribution checks. Guidance-only edits need reference/discovery validation and license freshness when notices change.
