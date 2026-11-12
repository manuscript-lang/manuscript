[Wiki](../index.md) › [Repository maintenance](index.md)

# PR checks run Linux only; Windows and macOS run on main

Verified: PR #1548 merged green on Linux alone; the full-matrix run then showed `many_joins` fixed but exposed two Windows-only e2e hangs (`workers`, `http-request-deadline`, #1557) that had never run there. Linux-green does not establish parity. The six platforms run on the scheduled check of `main`; a manual run's `os` input (`windows`, `darwin`, `linux`) runs one platform on a branch.

Decision (2026-11): no merge queue. It built the full matrix for each of up to 5 stacked refs per group and restarted on every outside merge, so PRs auto-merge on the Linux legs (amd64 and arm64) and a red `main` is fixed or reverted.

Reversed (2026-11-09): a path list (`.github/platform-paths.txt`) added Windows and macOS legs to PRs, but it kept growing (#3254 added `crates/ms-lsp/` and itself triggered the full matrix via the list's own entry) and made PR runs slow and costly. The owner's decision: PRs run Linux only; the scheduled main run covers all six platforms and a host failure is fixed or reverted there. Dispatch `cicd.yml` with `os` on the branch for host-sensitive changes.

Apply when: changing runtime, sockets, workers, paths, linking, or anything host-specific.
Evidence: `.github/workflows/cicd.yml` (`workflow_dispatch`); [create-pr](../../skills/create-pr/SKILL.md#merging).
Verify: the dispatched run's Windows and macOS jobs pass; no test was skipped or gated to get there.

Lesson (2026-11-09): #3227 and #3234 added `ms-lsp` signature-help tests that used `file:///x.ms` documents, which name no real directory on Windows. Tests that analyze a document use `Workspace::uri`, not a literal Unix path.

Verified (2026-11-10): a manual run can cover only one OS, so it must not suppress the scheduled six-platform check for the same commit. Only scheduled and manual `all`/`linux` runs produce the book for Pages. `tests/workflows/cicd.test.cjs` exercises the actual scheduling script and deployment condition.

Lesson (2026-11-12): #3635 added `sys::prefer_huge_pages` to `ms-rt/src/sys.rs` with a non-Linux no-op and broke the Windows build on `main`: Windows compiles `sys_windows.rs` instead of `sys.rs`, so a `cfg` fallback in `sys.rs` never reaches it. A new `sys::` function needs a definition in both files, and a runtime change gets a dispatched Windows run before it merges. Windows has no `madvise` equivalent (large pages need `MEM_LARGE_PAGES` at allocation and a lock-memory privilege), so its version is a documented no-op.
