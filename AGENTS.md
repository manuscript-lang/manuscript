# Repository guidance

- Read and apply [language design taste](skills/language-design-taste/SKILL.md) when proposing or reviewing language, standard library, runtime, compiler, or tooling changes.
- Current design documents and explicit user instructions take precedence over these preferences.
- Before implementing or reviewing Manuscript changes, read [manuscript-change](skills/manuscript-change/SKILL.md) and consult the relevant experts it routes to.
- When work establishes a durable lesson or the user corrects a recurring mistake, apply [change-memory](skills/change-memory/SKILL.md) to preserve it alongside the change.

## Repository layout

- Reusable Go packages live in `pkg/`; executable entrypoints live in `cmd/`, and private CLI/native helpers live in `internal/`.
- Keep root Go embed carriers beside `go.mod`, `vendor/`, `.msversion`, and the generated toolchain payload. Package moves must update imports, fixture paths, `scripts/repo-check/policy.json`, release inputs, and expert routes. See [repository architecture](documentation/contributing/architecture.md).

## Skills

- Shared skills live in `skills/`; `.agents/skills/` and `.claude/skills/` link to the same folders for native discovery.
- Read the relevant `SKILL.md` and its referenced files when using a skill. Preserve explicit-only invocation settings; `/skill-name` in upstream instructions means `$skill-name` in Codex.
- Use this `AGENTS.md` for repository guidance; do not create a separate `CLAUDE.md`.
- Matt Pocock's published skills are pinned in [mattpocock.lock.json](skills/mattpocock.lock.json), with their license in [LICENSE.mattpocock](skills/LICENSE.mattpocock).
