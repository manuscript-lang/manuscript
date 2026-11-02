# Wiki protocol

The wiki holds what an agent should remember across tasks: user decisions, non-obvious constraints, and failure mechanisms that code and docs do not make obvious. Canonical design pages, source declarations, and tests keep their authority; a page here gives the reason and points to them.

## Read

1. Before implementing or reviewing, open [index.md](index.md). Match the task and touched paths to a domain ([index.yml](index.yml) maps path globs to domains).
2. Open the domain `index.md`, pick pages by title, and read them. Follow evidence links only as needed. If exploration reaches another domain, read that domain too.
3. The user's explicit direction and current canonical design override a page. **Decision** records a user choice (a branch may not implement it yet), **Verified** needs code or checks behind it, **Open** is unresolved and imposes no rule. If sources disagree, check chronology and behavior, then report any material conflict.

## Update

Update the wiki in the same change when you learn something the next agent would otherwise get wrong: a user decision or correction, a failure mechanism, a rejected approach worth not retrying, or a stale page.

1. Edit the closest existing page first. Replace superseded advice; delete pages whose scope no longer applies.
2. Otherwise add one page in the domain folder and one line in that folder's `index.md`.
3. Keep a page short (about 10 lines): one lesson, one reason. Prefer a regression test or deterministic check for anything enforceable and link to it.
4. Do not record task status, logs, counts, obvious code descriptions, or text that a canonical doc owns. Keep scoped decisions scoped.
5. Read-only work may suggest wiki updates; edit only within authorized write scope.

## Page format

```markdown
[Wiki](../index.md) › [Domain](index.md)

# A concrete lesson title

Decision / Verified / Open: the constraint or failure mechanism and why it matters.

Apply when: the task that should reach this page.
Evidence: relative links to rules, code, tests, or the user decision.
Verify: an observable case that separates success from the mistake.
```
