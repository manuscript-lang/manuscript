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
- Keep skills, `.experts/` entries, and discovery links in sync when the change touches them (see [manuscript-change](../manuscript-change/SKILL.md#record-durable-lessons)).
- Do not merge with failing checks. Fix the cause; never skip or disable a test.
