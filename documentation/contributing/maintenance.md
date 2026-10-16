+++
title = "Maintenance and compatibility"
weight = 3
+++

# Maintain the repository

Keep changes small enough to trace from an observable example to their implementation and checks. The [architecture guide](architecture.md) maps ownership; `make repo-check` enforces dependency boundaries, embedded implementation sources, syntax handling, and release triggers. Update its policy only when the dependency is intentional and explain that choice in the PR.

## Refresh pinned inputs

Use the checkout SDK for maintenance commands. Make uses the checkout SDK and prepares the mandatory embedded build payload. Commands below deliberately modify tracked inputs; `make verify` only checks them.

| Change | Command and result |
| --- | --- |
| Go SDK | `toolchain/go/bin/go run ./scripts/maintenance go 1.25.1` reads the official release catalog and updates `.go-version`, all six archive checksums, and the module's Go language version. Substitute the desired exact version, then run `make setup` |
| Node | `toolchain/go/bin/go run ./scripts/maintenance node 24.13.0` updates `.node-version`, shared by CI. Install that version, then run `npm ci` in `extensions/vscode` |
| Go dependencies | Edit requirements or review a dependency PR, then run `make vendor-refresh` to tidy the module, rebuild `vendor/`, and refresh the notice inventory |
| Extension dependencies | Update `extensions/vscode/package.json`, run `npm install --package-lock-only --ignore-scripts` there, then `npm ci` and `npm run package -- --allow-missing-repository` |
| License inventory | `make licenses` records the paths and SHA-256 hashes of vendored dependency/theme/skill license notices; `make licenses-check` detects drift. This inventory identifies notices; it is not a legal assessment |
| Linters | Update `scripts/devtools.env` and the matching verified ShellCheck checksums, then `make setup`. Staticcheck, actionlint, and ShellCheck remain checkout-local in `.tools/` |

Dependabot groups weekly Go, extension, and Actions updates into reviewable PRs. Updates receive the same verification as other changes and are not automatically merged. Preserve vendor notices and run the relevant native/packaged checks before merging dependency changes. Review SDK statements in the implementation guide when changing the Go pin.

## Public compatibility

Treat Manuscript syntax and standard signatures, exported frontend Go APIs, CLI flags/statuses, diagnostic codes and JSON schemas, project configuration, and artifact metadata as contracts. Correcting diagnostic prose may change wording while retaining the code's meaning. Internal package structure and generated Go identifiers are implementation details, except where the debugger's checked metadata exposes a mapping.

Before 1.0, an intentional incompatible public change belongs in a minor release; patch releases contain compatible fixes. From 1.0 onward, incompatible changes require a major release. State the affected source or command and its migration in the PR. For a deprecation, document the replacement and intended removal release, and test both during the transition. Explicit user-directed removals take precedence; this policy does not restore retired APIs.

Compiler/runtime/target changes alter build identity even without a source-language compatibility change. Do not claim native binary reproducibility across environments or compatibility for undocumented internal layouts.

## Prepare a release

1. Run `toolchain/go/bin/go run ./scripts/maintenance version 0.1.1`, substituting the release version. It updates `.msversion`. The CLI, build identity, and book read this single version.
2. Run `make verify-full`, extension packaging/debugger checks, and review the six-target distribution workflow.
3. Merge the release changes, then create the matching `v<version>` tag. Tagging publishes only after all six packaged binaries pass standalone verification. Review GitHub's generated release notes.

A version update does not create a tag or publish anything. Documentation archives are separate preserved sites; adding a dropdown entry does not create an archive.

## Keep the feedback loop healthy

Use `make verify` while editing and `make verify-full` before merging changes that reach native behavior. CI runs fast checks first, then conformance, races, fuzzing, host matrices, editor/debugger integration, and release verification. The stable `Language checks / test` gate fails if any dependency job fails or is cancelled.

Add tests at the boundary where a regression is observable. Use source acceptance/rejection and transcripts for language changes; use barriers and channels for lifecycle ordering; use the packaged binary for installation claims. Coverage includes dependency packages but excludes execution inside separately built native programs. Treat low coverage as a prompt to inspect missing behavior, not as a reason to add tests that mirror implementation.
