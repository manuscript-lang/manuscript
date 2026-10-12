# Manuscript skills

[AGENTS.md](../AGENTS.md#domain-skills) routes future sessions to repository-specific workflows. `skills/` is the shared source; `.agents/skills/` and `.claude/skills/` hold discovery symlinks. The imported general-purpose collection, installer, lockfile, and license were removed with that collection.

## Maintain the catalog

- Each skill needs `SKILL.md` with `name` and `description` frontmatter, a concrete trigger, repository entry points, and applicable checks. Match the folder and frontmatter names.
- Keep common tracing in `manuscript-change`, taste in `language-design-taste`, and durable lessons in `.experts/` through `change-memory`. Link to specifications instead of copying them.
- Keep `agents/openai.yaml`, both discovery links, and the AGENTS.md routing table aligned.
- Check Markdown targets, frontmatter, metadata, and symlinks after catalog edits. Search for removed names. Regenerate changed third-party notices with `make licenses`; verify with `make licenses-check`.

## Conversation evidence

These user requests explain the workflows; they do not establish that every requested feature has shipped. Use current source, guides, tests, and [expert knowledge](../.experts/README.md) for behavior.

| Conversation | Durable direction |
| --- | --- |
| [Write language design taste skill](codex://threads/01a12bda-40f6-7761-8b27-6c8a0f8d9cb8) | Concise, bulleted preferences; shared Codex/Claude skills through AGENTS.md. The current cleanup replaces the earlier imported collection. |
| [Build Manuscript improvement skills](codex://threads/01a12e53-e25e-7913-b35d-92093dc611e5) | Preserve corrections and failure mechanisms so later changes do not repeat mistakes. |
| [Handle multiline function arguments](codex://threads/01a12ed2-aa86-7536-a7bd-47d68c2f201a) | Valid syntax must retain positions/scopes in incomplete editor snapshots. |
| [Fix navigation within stdlib](codex://threads/01a12eec-3373-7788-ad57-e7846ba1c016) | Navigation continues within standard source after the initial jump. |
| [Simplify concurrency model](codex://threads/01a12e6e-1c9c-7405-824b-4c2a71ecc024) | Local Queue, explicit synchronization, omitted capacity unbounded; later corrections supersede earlier alternatives. |
| [docs revamp](codex://threads/01a130d5-dd06-70bd-bed0-4fc43c9f503a) | Explain unfamiliar contracts with plain language and concrete uses. |
| [Organize Manuscript codebase](codex://threads/01a12f20-92fb-77af-8dc8-ebbdba85f00d) | Simplify duplicated work/layers; generated HTML belongs in ignored artifacts; verify publication. |
| [Revamp and solidify stdlib](codex://threads/01a13126-1245-730b-9e5d-16ca2dc7501f) | Audit parity/grouping, optional limits/timeouts, remove Pools/Lease, make Equal/Hashable interfaces, add priority queue, investigate scheduling consolidation/naming. In progress when this catalog was updated; reconcile with the checkout rather than claiming completion. |
