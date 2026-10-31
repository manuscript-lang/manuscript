[Wiki](../index.md) › [Repository maintenance](index.md)

# PR checks skip Windows, so dispatch the full matrix

Verified: PR #1548 merged green on Linux alone; the full-matrix run then showed `many_joins` fixed but exposed two Windows-only e2e hangs (`workers`, `http-request-deadline`, #1557) that had never run there. Linux-green does not establish parity.

Apply when: changing runtime, sockets, workers, paths, linking, or anything host-specific.
Evidence: `.github/workflows/cicd.yml` (`workflow_dispatch`); [create-pr](../../skills/create-pr/SKILL.md#merging).
Verify: the dispatched run's Windows and macOS jobs pass; no test was skipped or gated to get there.
