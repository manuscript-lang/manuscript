[Wiki](../index.md) › [Repository maintenance](index.md)

# Repository tools are Manuscript programs

Verified: runners, packaging, and checks live in `tools/*.ms` and run with `ms run tools/<name>.ms`, not as shell or Python scripts. Only what must run before any `ms` exists stays outside: `cmake/toolchain/fetch-mingw.sh` and the lld pins in `cmake/toolchain/lld.lock`. A new tool imports `tools/lib.ms` (host detection, `run`, `capture`, stats runtime setup), takes paths relative to the repository root, and returns its exit status from `main` (0 to 125). Tools that change directory (`e2e.ms` projects) run them serially, because the working directory is process-wide. Workflow lint (actionlint, shellcheck) was dropped with the shell scripts.

Apply when: adding a CI step, Make target, or repository automation.
Evidence: [shared helpers](../../../tools/lib.ms), [Makefile](../../../Makefile), CI.
Verify: `ms run tools/conform.ms`, `tools/conform.ms`, `tools/count-check.ms` pass on Linux, macOS, and Windows CI.

Verified (2026-11-10): `tools/package.ms` must copy the repository `LICENSE` into every binary archive with a readable file mode. The local distribution check and both CI packaging paths compare the extracted file with the source, so successful compiler smoke tests alone cannot hide a missing or altered license.

Verified (2026-11-10): the extension is bundled with esbuild and packaged without `node_modules`, so upstream notice files must be carried separately. `extensions/vscode/build.js` derives the packages from esbuild inputs and writes their exact notice texts into `dist/THIRD-PARTY-NOTICES.txt`, which the VSIX includes. `tests/notices.test.js` covers missing notices, deduplication, scoped/nested paths and byte-preserving text.

Verified (2026-11-24): the pinned LLVM library is fetched by `cmake/FetchLlvmLib.cmake` (CMake target `llvm-lib`, which exports `MS_LLVM` through `GITHUB_ENV`), not by a Manuscript tool. The first version was `tools/fetch-llvm-lib.ms`, but compiling any Manuscript program needs this library, so the fetcher needed what it fetches; with neither present `ms run` crashed (#6843). A tool that must run before ms can compile belongs in CMake, which downloads, checks the digest and unpacks on every platform; a shell script trips the new-script lint rule.

Verified (2026-11-23): `make build` also runs the fetch (non-fatal when offline), and the build embeds the fetched library's path as `MS_BUILD_LLVM` (`cmake/MsRuntimePackage.cmake`), so a build tree loads LLVM in-process like an install; the library is required. Before it was, a dev build without it took the `opt`/`llc` child-process route, about 20% to 35% slower (jsonrt Debug build 0.42 s against 0.27 s; router Debug test 5.3 s against 4.4 s).

Decision (Chinmay, 2026-11-25): the `opt` and `llc` child-process route is removed. `ms` has one code path, in-process through libLLVM; an unloadable or missing library is the error `cannot load the LLVM library (MS_LLVM names it)`, and `MS_LLVM=none`, `MS_OPT` and `MS_LLC` no longer exist. The package no longer ships `llc`. llvm-bundle still builds the `llvm-tools` archive (Chinmay: it can stay for now); manuscript no longer fetches it and its lock files dropped the digests, so deleting it from llvm-bundle later changes nothing here. Reason: every package ships the library, and two routes doubled testing and upkeep.
