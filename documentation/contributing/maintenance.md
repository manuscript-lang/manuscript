+++
title = "Maintenance and compatibility"
weight = 3
+++

# Maintain the repository

Keep changes traceable from an observable example to implementation and checks. The [architecture guide](architecture.md) maps ownership; `make repo-check` enforces nested-match rules, `.ms` formatting, release pins, and workflow triggers. Change its rules only for an intentional reason, and explain it in the PR.

## Refresh pinned inputs

These changes modify tracked inputs; `make verify` only checks them.

| Change | Command and result |
| --- | --- |
| Node | Edit `.node-version`; install it, then `npm ci` in `extensions/vscode` |
| C dependencies | Vendor under `src/third_party/` and update `c-libs.lock`; then `make licenses` |
| Extension dependencies | Edit `extensions/vscode/package.json`, run `npm install --package-lock-only --ignore-scripts`, then `npm ci` and `npm run package -- --allow-missing-repository` |
| License inventory | `make licenses` records each vendored C library's name, version and license file (from `src/third_party/c-libs.lock`) with the notice's SHA-256; `make licenses-check` detects drift. It is not a legal assessment |

Dependabot groups weekly updates (npm, GitHub Actions) into PRs with normal verification and no auto-merge; run `make verify-full` before merging.

## Public compatibility

The public contracts are syntax, standard signatures, CLI flags and statuses, diagnostic codes and JSON schemas, project configuration, and artifact metadata. Diagnostic wording may change if the code keeps its meaning. Crate structure and generated symbol names are internal.

- Versions are dates, `YYYY.MM.PATCH` with no leading zero on the month.
- State the affected source or command and its migration in the PR.
- A deprecation documents the replacement and removal release, and tests both.
- Every removed or renamed spelling (syntax, method, module, flag) adds a snippet to `tests/checks/removed/` in the same change. It starts with `// removed: <old spelling>`, `// use: <text the error must contain>` and `// fix: <text the file holds after `ms check --fix`>`.
  - `make removed-check` fails unless `ms check` rejects the snippet with an error naming the replacement and `--fix` rewrites it so `ms check` passes. When the check fails, fix the diagnostic, not the snippet.
  - A removal that no mechanical edit can carry writes `// fix: null: <why>`. Reviewers should question each one.
- List breaking changes with their migration in the release notes. The user-facing list of frozen contracts is [what is frozen](../core-language/stability.md).
- Explicit user-directed removals win; this policy does not restore retired APIs.
- Compiler, runtime, or target changes alter build identity. Do not claim cross-environment binary reproducibility.

## Prepare a release

1. Update `.msversion`, which the CLI, build identity, and book read, and keep `extensions/vscode/package.json` at the same version; `make repo-check` fails when they disagree.
2. Run `make verify-full`, extension packaging, and review the six-target distribution workflow.
3. When a newer release replaces the book of an older one, add that release to `website/data/docs_versions.toml` (its `manuscript-docs` archive is built and attached by the release workflow).
4. Merge, then tag `v<version>`. Tagging publishes only after all six binaries pass standalone verification, including an exact copy of the repository `LICENSE` in each archive. Review the generated release notes.

A version update creates no tag. The release workflow also attaches the release's book as `manuscript-docs-<version>.tar.gz`; a dropdown entry only links to it.

The workflow also attaches the agent skill as `manuscript-skill.tar.gz` and its checksum, packed by `toolchain/package-skill.sh` from `agent-skill/` and stamped with `.msversion`, so the file name is the same on every release. `website/static/install-skill.sh` and `install-skill.ps1` download it; the release rehearsal installs it on all six targets.

## Keep the feedback loop healthy

Use `make verify` while editing and `make verify-full` before merging native changes. The `Platform checks` gate fails if any platform job fails or is cancelled.

- Test where a regression is observable: source fixtures and the conformance corpus for language behavior, the packaged binary for installation.
