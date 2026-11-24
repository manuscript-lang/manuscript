# Proposals

A proposal records a design decision before it is built: the problem, the rule, the evidence, and what lost. The format follows the Swift Evolution template, trimmed to what Manuscript needs. Start from [TEMPLATE.md](TEMPLATE.md); [author-proposal](../../skills/author-proposal/SKILL.md) is the writing workflow.

## When one is required

- A language change: syntax, types, semantics, imports, interfaces, or the memory model.
- A standard-library API that adds, renames, or removes a public name, or changes ownership of an existing one.
- A change across layers or packages (new representation, pass, or restructure), as AGENTS.md requires.
- A user-visible tooling or CLI contract change.

Bug fixes, internal refactors inside one layer, and docs need none. When unsure, write the Summary and Motivation; if they fit in ten lines, open the PR with them instead.

## How

1. Copy `TEMPLATE.md` to `design/proposals/<kebab-name>.md`. Names are plain and say the change; no numbers.
2. Ground it in the guide, stdlib, and past proposals; check every `.ms` example with `ms check`.
3. Open it in the implementing PR (never alone). A change that alters the language or user-visible behavior waits for the owner's decision in Status before it merges; other proposals go through the skeptical review in AGENTS.md.
4. Keep Status current: Proposed, Approved, Implemented, Rejected, or Withdrawn, with the date and commit. Update in place; no changelog.
5. Once implemented, cut it to Summary, Status, and the non-obvious decisions, and move durable lessons to [`design/wiki/`](../wiki/index.md).

## What differs from Swift's template

- No review manager, forum threads, or ABI section; the review is the PR and the owner's decision.
- Added: fit with the memory model, agent ergonomics, measured benefit, and platform parity, because those decide Manuscript changes.
- Length is capped (60 to 100 lines) and every line must change the decision or the build.
