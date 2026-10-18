+++
title = "Maintenance and compatibility"
weight = 3
+++

# Maintain the repository

Keep changes traceable from an observable example to implementation and checks. The [architecture guide](architecture.md) maps ownership; `make repo-check` enforces dependency boundaries, embedded sources, syntax handling, and release triggers. Change its policy only for an intentional dependency, and explain it in the PR.

## Refresh pinned inputs

Use the checkout SDK. These commands modify tracked inputs; `make verify` only checks them.

| Change | Command and result |
| --- | --- |
| Go SDK | `toolchain/go/bin/go run ./scripts/maintenance go 1.25.1` (use the exact version) updates `.go-version`, six archive checksums, and the module Go version; then `make setup` |
| Node | `toolchain/go/bin/go run ./scripts/maintenance node 24.13.0` updates `.node-version`; install it, then `npm ci` in `extensions/vscode` |
| Go dependencies | Edit requirements, then `make vendor-refresh` (tidy, rebuild `vendor/`, refresh notices) |
| Extension dependencies | Edit `extensions/vscode/package.json`, run `npm install --package-lock-only --ignore-scripts`, then `npm ci` and `npm run package -- --allow-missing-repository` |
| License inventory | `make licenses` records paths and SHA-256 hashes of vendored notices; `make licenses-check` detects drift. It is not a legal assessment |
| Linters | Update `scripts/devtools.env` and ShellCheck checksums, then `make setup`; tools stay in `.tools/` |

Dependabot groups weekly updates into PRs with normal verification and no auto-merge; run native and packaged checks before merging.

## Public compatibility

Contracts: syntax, standard signatures, exported frontend Go APIs, CLI flags and statuses, diagnostic codes and JSON schemas, project configuration, and artifact metadata. Diagnostic wording may change if the code keeps its meaning. Package structure and generated Go identifiers are internal, except where debugger metadata exposes them.

- Before 1.0, incompatible public changes go in a minor release; patches stay compatible. From 1.0, they need a major release.
- State the affected source or command and its migration in the PR.
- A deprecation documents the replacement and removal release, and tests both.
- Explicit user-directed removals win; this policy does not restore retired APIs.
- Compiler, runtime, or target changes alter build identity. Do not claim cross-environment binary reproducibility.

## Prepare a release

1. Run `toolchain/go/bin/go run ./scripts/maintenance version 0.1.1` (your version). It updates `.msversion`, which the CLI, build identity, and book read.
2. Run `make verify-full`, extension packaging and debugger checks, and review the six-target distribution workflow.
3. Merge, then tag `v<version>`. Tagging publishes only after all six binaries pass standalone verification. Review the generated release notes.

A version update creates no tag. Documentation archives are separate preserved sites; a dropdown entry creates none.

## Keep the feedback loop healthy

Use `make verify` while editing and `make verify-full` before merging native changes. The `Language checks / test` gate fails if any dependency job fails or is cancelled.

- Test where a regression is observable: source fixtures and transcripts for language, barriers for lifecycle ordering, the packaged binary for installation.
- Coverage excludes separately built native programs; low coverage prompts inspection, not mirror tests.
