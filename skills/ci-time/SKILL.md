---
name: ci-time
description: Investigate and cut pull request CI or test time without weakening coverage. Use when CI is slow, the Time budget check fails, or a test is added.
---

# Investigate CI time

Read [the CI budget](../../wiki/repository/pull-request-ci-has-a-ten-minute-budget.md) first. The budget is strict: two Linux jobs, each under 600 s.

1. **Measure.** Take the latest PR run's job log: step times and the slowest-tests list. Do not guess; profile one slow test with `valgrind --tool=callgrind` or a timer.
2. **Remove redundant work before shrinking inputs.** Share one checker session, build once, cache setup, drop work another test already covers, sample instead of looping over every position. Shrink an input only when nothing cheaper is left, and keep what the test proves.
3. **Keep coverage and checks.** Do not skip, shard, or gate a test per platform or arch, and do not move a test to `main` only to meet the budget.
4. **Show before/after** per step in the PR, from CI runs rather than local timings. A new test must fit the budget or something else is cut.
5. **List every cut.** Each sampled loop, fewer combinations or shorter input goes in the PR body with what it no longer covers, so the owner can ask for it back.
6. **Record** a lesson in the CI budget page; land with [create-pr](../create-pr/SKILL.md).
