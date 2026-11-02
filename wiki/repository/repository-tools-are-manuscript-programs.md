[Wiki](../index.md) › [Repository maintenance](index.md)

# Repository tools are Manuscript programs

Verified: runners, packaging, and checks live in `tools/*.ms` and run with `ms run tools/<name>.ms`, not as shell or Python scripts. Only what must run before any `ms` exists stays outside: `toolchain/fetch-mingw.sh` and the lld pins `ms-clif/build.rs` reads. A new tool imports `tools/lib.ms` (host detection, `run`, `capture`, stats runtime setup), takes paths relative to the repository root, and returns its exit status from `main` (0 to 125). Tools that change directory (`e2e.ms` projects) run them serially, because the working directory is process-wide. Workflow lint (actionlint, shellcheck) was dropped with the shell scripts.

Apply when: adding a CI step, Make target, or repository automation.
Evidence: [shared helpers](../../tools/lib.ms), [Makefile](../../Makefile), [CI](../../.github/workflows/cicd.yml).
Verify: `ms run tools/e2e.ms`, `tools/conform.ms`, `tools/count-check.ms` pass on Linux, macOS, and Windows CI.
