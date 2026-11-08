[Wiki](../index.md) › [Repository maintenance](index.md)

# PR checks run Windows and macOS only for platform-sensitive paths

Verified: PR #1548 merged green on Linux alone; the full-matrix run then showed `many_joins` fixed but exposed two Windows-only e2e hangs (`workers`, `http-request-deadline`, #1557) that had never run there. Linux-green does not establish parity. The six platforms run on every push to `main`; a manual run's `os` input (`windows`, `darwin`, `linux`) runs one platform on a branch.

Decision (2026-11): no merge queue. It built the full matrix for each of up to 5 stacked refs per group and restarted on every outside merge, so PRs auto-merge on the Linux legs (amd64 and arm64) and a red `main` is fixed or reverted.

Update (2026-11-08): relying on each author to dispatch failed. #3067, #3070, #3076 and #3089 merged green on Linux and broke Windows or macOS on `main`; the authors did not know their change was host-sensitive. A PR whose changed files match `.github/platform-paths.txt` now also runs windows-amd64 and darwin-arm64 (`tests` and `conformance`), and `Platform checks` requires them. Add a pattern there when a host-only failure reaches `main` from a path it does not list. The arm64 Windows and amd64 macOS legs still run only on `main`.

Apply when: changing runtime, sockets, workers, paths, linking, or anything host-specific.
Evidence: `.github/workflows/cicd.yml` (`workflow_dispatch`); [create-pr](../../skills/create-pr/SKILL.md#merging).
Verify: the dispatched run's Windows and macOS jobs pass; no test was skipped or gated to get there.
