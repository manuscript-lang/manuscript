[Wiki](../index.md) › [Repository maintenance](index.md)

# Pull request CI has a five-minute budget

Decision (Chinmay): a pull request's CI must finish in under 5 minutes, and a new test must fit the budget or something else is cut.

- Two jobs per PR, one per Linux arch (amd64 and arm64), each running its whole suite. No sharding, no extra runners, and no per-arch or per-platform skipping of a test.
- Budget per job: about 300 s in total. The conformance corpus takes about 170 s (Cranelift, every phase) and is not trimmed. Rust tests, build, lint and setup share the remaining 130 s.
- Pull requests build programs with Cranelift. The LLVM suite (LLVM corpus, release gates, the `llvm` Rust tests) runs on `main` every 30 minutes and on pull requests that touch LLVM-specific code (`crates/ms-mir-llvm`, `crates/ms-build/src/llvm*`, the LLVM tests, `toolchain/`); the filter lives in `.github/actions/rust-scope`.
- A new Rust test is cheap or it replaces another: no test over 2 s without a reason, no per-position loops over a whole file (sample them), no spawning `ms` for a case an in-process call covers, no work the conformance corpus already does. Measure with the slowest-tests list in the job log.
- Cheapest first fixes found so far: share one checker session instead of rebuilding the standard library per check; cache per-thread test setup; optimize the hot crates of loop-heavy tests with `[profile.dev.package.<crate>]` in the root `Cargo.toml`; cache the native runtime build; profile one `ms test` with `valgrind --tool=callgrind` before guessing (Cranelift's debug assertions were a third of the compile instructions; the dev profile now turns them off for the Cranelift crates).
- Decision (Chinmay, 2026-11-14): meet the budget by removing redundant work (shared sessions, one build, work another test already does), not by shrinking test inputs or dropping coverage. The Cranelift IR verifier stays on in PR CI. See [ci-time](../../skills/ci-time/SKILL.md).
- Measured on a PR run (4 cores): setup 46 s, test build 166 s, Rust tests 214 s, corpus 189 s, lint 50 s, so the fixed costs alone exceed 300 s on amd64; each `ms run|test` corpus fixture compiles its own program (about 0.5 s), only `check` is batched.
- CI reports it: the `Time budget` job in `cicd.yml` annotates a pull request whose Linux job ran over 300 s. It is report-only (a warning, never a failure) until the budget is met, so it cannot block merging; then make it fail again.

Apply when: adding or changing a test, a CI step or a workflow.
Evidence: [cicd.yml](../../.github/workflows/cicd.yml), [rust-scope](../../.github/actions/rust-scope/action.yml), [AGENTS.md](../../AGENTS.md).
Verify: the latest pull request run shows both Linux jobs under 300 s and no budget warning.
