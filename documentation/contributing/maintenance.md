+++
title = "Maintenance and compatibility"
weight = 3
+++

# Maintain the repository

Keep changes traceable from an observable example to implementation and checks. The [architecture guide](architecture.md) maps ownership; `make repo-check` enforces nested-match rules, `.ms` formatting, release pins, workflow triggers, and the `unsafe` boundary. Change its rules only for an intentional reason, and explain it in the PR.

## Refresh pinned inputs

These changes modify tracked inputs; `make verify` only checks them.

| Change | Command and result |
| --- | --- |
| Rust toolchain | Edit `rust-toolchain.toml`; see [Rust toolchain](rust-toolchain.md) |
| Node | Edit `.node-version`; install it, then `npm ci` in `extensions/vscode` |
| Cargo dependencies | Edit `Cargo.toml` and refresh `Cargo.lock`; then `make licenses` |
| Extension dependencies | Edit `extensions/vscode/package.json`, run `npm install --package-lock-only --ignore-scripts`, then `npm ci` and `npm run package -- --allow-missing-repository` |
| License inventory | `make licenses` records each locked Cargo crate's name, version, and declared SPDX license (from `cargo metadata --locked`) plus SHA-256 hashes of bundled notices; `make licenses-check` detects drift. It is not a legal assessment |

Dependabot groups weekly updates (Cargo, npm, GitHub Actions) into PRs with normal verification and no auto-merge; run `make verify-full` before merging.

## Public compatibility

Contracts: syntax, standard signatures, CLI flags and statuses, diagnostic codes and JSON schemas, project configuration, and artifact metadata. Diagnostic wording may change if the code keeps its meaning. Crate structure and generated symbol names are internal.

- Before 1.0, incompatible public changes go in a minor release; patches stay compatible. From 1.0, they need a major release.
- State the affected source or command and its migration in the PR.
- A deprecation documents the replacement and removal release, and tests both.
- Explicit user-directed removals win; this policy does not restore retired APIs.
- Compiler, runtime, or target changes alter build identity. Do not claim cross-environment binary reproducibility.

## Prepare a release

1. Update `.msversion`, which the CLI, build identity, and book read, and keep `extensions/vscode/package.json` at the same version; `make repo-check` fails when they disagree.
2. Run `make verify-full`, extension packaging, and review the six-target distribution workflow.
3. Merge, then tag `v<version>`. Tagging publishes only after all six binaries pass standalone verification. Review the generated release notes.

A version update creates no tag. Documentation archives are separate preserved sites; a dropdown entry creates none.

## Keep the feedback loop healthy

Use `make verify` while editing and `make verify-full` before merging native changes. The `Language checks / test` gate fails if any dependency job fails or is cancelled.

- Test where a regression is observable: source fixtures and the conformance corpus for language behavior, the packaged binary for installation.
