---
name: create-issue
description: File a Manuscript issue that states the problem with evidence, expected versus actual behavior, a proposed direction, and alternatives.
---

# Create an issue

Use when filing or rewriting an issue. Search existing issues and PRs first and link duplicates instead of filing again. Verify behavior against current source, tests, and canonical guides; see [manuscript-change](../manuscript-change/SKILL.md).

## Body

If `.github/ISSUE_TEMPLATE/` exists, use its form and put these sections in it.

1. **Problem**: what is wrong or missing and who it affects. Include a minimal repro (smallest `.ms` source plus the command run) or other evidence such as a diagnostic, failing test, or `file:line`. State the checkout or version.
2. **Expected vs actual**: what should happen, what happens, with exact output. Cite the guide or test that defines the expected behavior; mark it as inferred when none does.
3. **Proposed direction**: the suggested fix or design, and the surfaces it reaches (syntax, checker, runtime, stdlib, tooling, docs). For a bug where the fix is unknown, say so.
4. **Alternatives**: other approaches and why they were set aside. Omit only when none are known, and say that.

## Rules

- One problem per issue.
- Title: specific and under about 70 characters; name the symptom, not the guess at the cause.
- Separate observed facts from hypotheses.
- Repros must run as written; trim anything unrelated.
- When a PR will close the issue, write the PR with [create-pr](../create-pr/SKILL.md) and link it.
