# Manuscript skills

[AGENTS.md](../AGENTS.md#domain-skills) routes future sessions to repository-specific workflows. `skills/` is the shared source; `.agents/skills/` and `.claude/skills/` hold discovery symlinks. The imported general-purpose collection, installer, lockfile, and license were removed with that collection.

[Simplify](simplify/SKILL.md) turns simplification requests into concrete removal
of duplicated behavior, unnecessary work, special cases, and confusing layers.
It uses the affected domain skills for contract checks.

[Author proposal](author-proposal/SKILL.md) sets the structure, technical style,
grounding in the language, `ms check`-verified examples, component tables, and
a simplification pass for design proposals.

[Bug bash](bug-bash/SKILL.md) and [perf bash](perf-bash/SKILL.md) are the repeated
probe-fix-file and measure-fix-record workflows.

## Maintain the catalog

- Each skill needs `SKILL.md` with `name` and `description` frontmatter, a concrete trigger, repository entry points, and applicable checks. Match the folder and frontmatter names.
- Keep common tracing in `manuscript-change`, taste in `language-design-taste`, and durable lessons in `wiki/` through its "Record durable lessons" section. Link to specifications instead of copying them.
- Keep `agents/openai.yaml`, both discovery links, and the AGENTS.md routing table aligned.
- Check Markdown targets, frontmatter, metadata, and symlinks after catalog edits. Search for removed names. Regenerate changed third-party notices with `make licenses`; verify with `make licenses-check`.

