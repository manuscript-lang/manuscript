---
name: fix-issue
description: Fix a GitHub issue end to end: label it, find the root cause, test, open the PR with auto-merge, and close it after merge. Use for "fix issue" requests.
---

# Fix an issue

1. **Claim.** Search open PRs and issues for duplicates, then add the `in progress` label to the issue.
2. **Reproduce** with the smallest program on current `main`. Read [manuscript-change](../manuscript-change/SKILL.md) and the wiki checklists for the surfaces it touches.
3. **Find the root cause.** Fix it where the wrong behavior starts, in the general layer. No special case keyed on a name, an op shape or one benchmark or test; if only a hack fits, say so on the issue instead of shipping it. A temporary workaround needs its own issue naming the removal condition.
4. **Test** at the layer that fails for the right reason, within the [CI budget](../ci-time/SKILL.md). Never skip a platform; dispatch the Windows or macOS CI for platform-sensitive changes.
5. **Open the PR** with [create-pr](../create-pr/SKILL.md): ready for review, squash auto-merge on, `Fixes #N` in the body. Start the next slice on a stacked branch instead of waiting on CI.
6. **After it merges**, remove the `in progress` label, close every issue the PR fixes and check each is closed, and delete any workaround the fix made obsolete.
