[Wiki](../index.md) › [Repository maintenance](index.md)

# Repository tools are Manuscript programs

Verified: runners, packaging, and checks live in `tools/*.ms` and run with `ms run tools/<name>.ms`, not as shell or Python scripts. Only what must run before any `ms` exists stays outside: `toolchain/fetch-mingw.sh` and the lld pins `ms-clif/build.rs` reads. A new tool imports `tools/lib.ms` (host detection, `run`, `capture`, stats runtime setup), takes paths relative to the repository root, and returns its exit status from `main` (0 to 125). Tools that change directory (`e2e.ms` projects) run them serially, because the working directory is process-wide. Workflow lint (actionlint, shellcheck) was dropped with the shell scripts.

Apply when: adding a CI step, Make target, or repository automation.
Evidence: [shared helpers](../../tools/lib.ms), [Makefile](../../Makefile), [CI](../../.github/workflows/cicd.yml).
Verify: `ms run tools/e2e.ms`, `tools/conform.ms`, `tools/count-check.ms` pass on Linux, macOS, and Windows CI.

Verified (2026-11-10): `tools/package.ms` must copy the repository `LICENSE` into every binary archive with a readable file mode. The local distribution check and both CI packaging paths compare the extracted file with the source, so successful compiler smoke tests alone cannot hide a missing or altered license.

Verified (2026-11-10): the extension is bundled with esbuild and packaged without `node_modules`, so upstream notice files must be carried separately. `extensions/vscode/build.js` derives the packages from esbuild inputs and writes their exact notice texts into `dist/THIRD-PARTY-NOTICES.txt`, which the VSIX includes. `tests/notices.test.js` covers missing notices, deduplication, scoped/nested paths and byte-preserving text.
