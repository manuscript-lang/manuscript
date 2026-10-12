# Manuscript expert knowledge

Expert files hold the reasons and failure modes that a future change should inherit. Canonical design pages, source declarations, and behavioral tests retain their own authority. This directory is ordinary Markdown and YAML so any agent can read it through `AGENTS.md`.

## Read and apply

Before implementation or review, select experts from [index.yml](index.yml) using both the task's meaning and affected paths. Patterns are repository-relative globs; they route knowledge, not file ownership. Read every relevant expert, and follow its evidence links only as needed. If exploration reveals another affected domain, consult that expert too.

The user's explicit direction and current canonical design take precedence over remembered guidance. An entry marked **Decision** establishes a user choice, not that every branch implements it. **Verified** requires code or checks that support the claim. **Open** records unresolved questions and cannot impose a rule. If sources disagree, trace their chronology and actual behavior; resolve what can be resolved from evidence and surface a material unresolved conflict.

## Learn and maintain

Capture a lesson when it changes how the next task should be implemented or reviewed. Repeated corrections deserve attention; a single explicit decision or demonstrated failure can also be enough. Update the closest existing entry before adding one. Replace superseded advice, retaining the previous alternative only when its rejection still prevents a likely mistake. Remove entries whose evidence or scope no longer applies.

Use a small entry:

```markdown
### A concrete lesson title
Decision / Verified / Open: the constraint or failure mechanism and why it matters.

Apply when: the next task that should reach this knowledge.
Evidence: relative links to canonical rules, code, regression tests, commits, or the originating user decision.
Verify: an observable case or existing check that distinguishes success from the mistake.
```

Support each factual claim with its own evidence. Historical chat links can establish what the user decided; current implementation claims need current code or execution evidence. Cite a recorded outcome as historical if it has not been rechecked. Avoid copying full conversations or duplicating specifications. Task status, check logs, feature counts, and obvious code descriptions belong elsewhere.

Prefer a regression test or an existing deterministic check for enforceable behavior, and link to it from the lesson. Keep scope-specific decisions scoped: skipping HTTP/3 on one request does not make it permanently forbidden. Read-only work may suggest memory updates; edit them only within authorized write scope.
