---
name: create-pr
description: Open or update a Manuscript pull request whose body states the problem, the proposed change, the alternatives considered, and how it was tested.
---

# Create a pull request

Use when opening a PR or rewriting a PR body. Run the checks from [development checks](../../documentation/contributing/development.md) first; [manuscript-change](../manuscript-change/SKILL.md) covers tracing the change.

## Body

Start from `.github/pull_request_template.md` and put these four sections first, in this order. Keep the template's Validation, Documentation, and Compatibility lines below them, only where they apply.

1. **Problem**: what is wrong or missing, who hits it, and a concrete trigger (input, command, or diagnostic). Not a restatement of the diff.
2. **Proposed change**: what the PR does and why that fixes the problem. Name the behavior that changes, not every file touched.
3. **Alternatives considered**: other approaches, including doing nothing, and why each was rejected. If none were viable, say why. Do not invent strawmen.
4. **Testing**: list each new or changed test by name and what it verifies (the behavior or regression it pins). Then the commands run with results. State what was not run and why. If no tests were added, say why none apply.

## Rules

- One problem per PR. Split unrelated fixes.
- Title: imperative, specific, under about 70 characters.
- Claims need evidence: link source, tests, or output. Say when something is inferred.
- Flag public API, diagnostic, manifest, or artifact changes and any migration.
- Keep skills, `wiki/` pages, and discovery links in sync when the change touches them (see [manuscript-change](../manuscript-change/SKILL.md#record-durable-lessons)).
- Do not merge with failing checks. Fix the cause; never skip or disable a test.

## Merging

- Open every PR ready for review, not as a draft, and enable squash auto-merge in the same step so it lands when required checks pass. The owner does not review PRs; an independent reviewer subagent challenges a structural proposal before implementation (see [AGENTS.md](../../AGENTS.md#shared-guidance-and-checks)).
- Auto-merge only waits for green CI, so keep the PR green: watch it, merge or rebase `main` on conflicts, and fix failures from the cause rather than re-running.
- A merge queue may be required. Do not bypass it or merge by hand while checks are pending.
- Keep a PR small enough that its CI stays meaningful: the corpus runs in four shards and tests in two partitions, so a PR that touches many crates waits on the slowest job.
