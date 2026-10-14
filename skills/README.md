# Manuscript skills

[AGENTS.md](../AGENTS.md#domain-skills) routes future sessions to repository-specific workflows. `skills/` is the shared source; `.agents/skills/` and `.claude/skills/` hold discovery symlinks. The imported general-purpose collection, installer, lockfile, and license were removed with that collection.

## Maintain the catalog

- Each skill needs `SKILL.md` with `name` and `description` frontmatter, a concrete trigger, repository entry points, and applicable checks. Match the folder and frontmatter names.
- Keep common tracing in `manuscript-change`, taste in `language-design-taste`, and durable lessons in `.experts/` through its "Record durable lessons" section. Link to specifications instead of copying them.
- Keep `agents/openai.yaml`, both discovery links, and the AGENTS.md routing table aligned.
- Check Markdown targets, frontmatter, metadata, and symlinks after catalog edits. Search for removed names. Regenerate changed third-party notices with `make licenses`; verify with `make licenses-check`.

