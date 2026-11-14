[Wiki](../index.md) › Repository maintenance

# Repository maintenance

Cleanup, CI, releases, Pages, Windows targets.

- [Build steps use the active Cargo invocation's checkout](build-steps-use-the-active-cargo-invocation-s-checkout.md): with a Cargo target directory shared between checkouts, Cargo reused an `xtask` executable whose compile-time `CARGO_MANIFEST_DIR` named the…
- [Documentation and site inputs keep their own homes](documentation-and-site-inputs-keep-their-own-homes.md): authored guides live in `documentation/`, site inputs in `website/`, and Pages output is built into ignored `.artifacts/book/` and deployed…
- [Pages deployment and Pages administration have different permissions](pages-deployment-and-pages-administration-have-different-per.md): the built-in workflow token with Pages write permission can deploy artifacts, but GitHub rejected changing the existing site's build type th…
- [Repository cleanup must remove duplicated work and layers](repository-cleanup-must-remove-duplicated-work-and-layers.md): codebase cleanup should make the implementation easy to follow, with clear layer boundaries and one implementation of each shared behavior.
- [Repository tools are Manuscript programs](repository-tools-are-manuscript-programs.md): runners, packaging, and checks are `tools/*.ms` run with `ms run`; only pre-`ms` bootstrap stays in `toolchain/`.
- [Windows Rust targets follow the native Rust host](windows-rust-targets-follow-the-native-rust-host.md): an emulated MSYS shell on Windows ARM64 reports `x86_64` from `uname -m`, while CI selects an `aarch64-pc-windows-msvc` Rust host and instal…
- [PRs run Linux only; Windows and macOS run on main](pr-checks-skip-windows-so-dispatch-the-full-matrix.md): host-sensitive changes dispatch `cicd.yml` on the branch.
- [Standing project rules from the owner](standing-project-rules-from-the-owner.md): PR auto-merge, platform parity, workarounds, Manuscript first, no new dependencies, memory model, glibc floor, minimal cross-thread state.
- [Pull request CI has a five-minute budget](pull-request-ci-has-a-five-minute-budget.md): two Linux jobs per PR under 300 s, conformance about 170 s, Rust tests the rest, no sharding, LLVM suite only on `main` and LLVM-touching PRs, new tests must fit.
- [Fixes address the root cause, not a name or shape](fixes-address-the-root-cause-not-a-name-or-shape.md): no special case keyed on a function name, an op shape or one benchmark; fix the general layer or report that only a hack fits.
