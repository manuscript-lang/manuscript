+++
title = "Development, checks, and publishing"
weight = 2
+++

# Development workflow

Run commands from the repository root. The pinned SDK is selected through `.go-version`; Node uses `.node-version`. Initial setup needs Make, curl, tar with xz support, a SHA-256 utility, and Internet access. Install the pinned Node version and Hugo Extended 0.146.7 or newer for editor and book work. A C compiler is required for race checks; Delve is required for native debugger integration.

```sh
make setup
make doctor
make verify
```

`make setup` installs verified Go and checkout-local pinned linters. `make doctor` reports missing or mismatched prerequisites without downloading anything. `make verify` runs read-only formatting/vet, correctness/simplification/unused-code lint, workflow/shell lint, repository invariants, fast unit tests, checked tutorial examples, generated API freshness, and license freshness. It does not build native conformance executables. Formatting corrections are explicit through `make fmt`; generated sources are explicit through `make docs` and `make licenses`.

For the complete native validation:

```sh
make verify-full
```

This additionally runs coverage/native conformance, race checks, strict/partial parser and compiler fuzzing, strict book/publication checks, and a standalone distribution test. Set `HUGO=/path/to/hugo` when it is not on PATH. `make build` creates the self-contained `ms` executable.

Tests that open HTTP/socket listeners need local loopback access. With a read-only home, choose writable `GOCACHE` and `GOPATH`, for example `/tmp/manuscript-go-cache` and `/tmp/manuscript-go`; `STATICCHECK_CACHE` defaults to ignored `.artifacts/staticcheck/`.

## Conformance and coverage

`make coverage` runs the entire Go suite and native conformance fixtures, with dependency-package instrumentation so runtime calls into `internal/hostos` contribute to coverage. It also executes complete tutorial modules directly from their Markdown source. The profile and HTML report live in `.artifacts/coverage/` and are uploaded by CI. Separately built native subprocesses are checked by observable expectations; their execution does not increase Go package coverage.

The end-to-end suite builds one CLI with a bounded setup, reuses it, and retains per-case temporary projects and processes. Accepted fixtures execute their test blocks; rejected cases verify diagnostics; transcript cases check evaluation order, cleanup, signals, host operations, and module boundaries. The harness imports the CLI implementation so source changes invalidate Go's test cache. For an explicit fresh native run, use `make e2e E2EFLAGS=-count=1`. Native build pins require empty GOFLAGS; pass test flags through E2EFLAGS instead.

Complete tutorial code fences carry a `manuscript-example` JSON comment specifying `test` or `run`, arguments, and expected stdout. `make examples-check` checks them without lowering; coverage executes them. Fragments remain clearly introduced as fragments. Do not maintain another copy of complete examples in test fixtures.

`make fuzz` exercises strict parsing, editor recovery, and compilation for ten seconds each. Set `FUZZTIME=1m` for longer runs. Preserve reproducible failures and add an observable regression before declaring a failure resolved.

`make dist` creates a single-binary archive in `dist/`. `sh scripts/package.sh <os> <arch>` packages Linux, macOS, or Windows for AMD64 or ARM64. `make dist-check` runs a copied binary outside the checkout with empty caches, no Go on PATH, and downloads disabled; compilation, source tools, LSP, debug builds, and profiles must work there. Archives include examples and dependency/SDK notices.

## Preview and publish the book

Author guides in `documentation/`; site configuration, assets, and the vendored theme live in `website/`. Reference Markdown/JSON comes from checked standard declarations. Keep lexical rules in the shared VS Code grammar at `extensions/vscode/syntaxes/manuscript.tmLanguage.json`.

```sh
make docs
make book-check
make book
hugo --source website server --bind 127.0.0.1 --port 4000 --renderToMemory
```

`make docs-check` detects stale generated references without rewriting them. `make book-check` validates strict Markdown links, highlighting, rendered API signatures, downloads, and obsolete routes under a project URL prefix. `make book` writes the production site into ignored `.artifacts/book/`. Generated HTML is not committed. Use `--cleanDestinationDir` so removed modules cannot survive in the published site.

The book uses Hugo Extended 0.146.7 in CI and vendored Hugo Book v13, with its license and upstream revision in `website/themes/hugo-book/`. Custom styling lives in `website/assets/_custom.scss`, behavior in `website/assets/docs.js`, and overrides in `website/layouts/`. Keep changes in these files instead of modifying the theme.

The shared `.msversion` supplies the current release labels. For preserved older sites, add version/URL entries in `website/data/docs_versions.toml`. Relative archive URLs respect the site's base URL; archives open their home page so newer routes do not produce broken links. Preserve snapshots separately from the cleaned current build. See [maintenance and compatibility](maintenance.md) for pin and release changes.

## Continuous integration

[CI/CD](https://github.com/manuscript-lang/manuscript/blob/main/.github/workflows/cicd.yml) runs on PRs and pushes to `main`, avoiding duplicate feature push/PR runs. Superseded PR runs are cancelled. [Language checks](https://github.com/manuscript-lang/manuscript/blob/main/.github/workflows/test-language.yml) starts with fast verification, then runs native coverage, races and fuzzing in separate jobs, host compatibility on Linux/macOS/Windows, and extension/native debugger integration. The built CLI is reused by the debugger job. SDK, module/build, lint tool, and npm caches use their pinned inputs.

The [distribution workflow](https://github.com/manuscript-lang/manuscript/blob/main/.github/workflows/release.yml) validates all six OS/architecture targets whenever Go sources or other build inputs change, including internal platform helpers. Manual runs produce artifacts; matching `v*` tags publish verified archives. For branch protection require **Build design book** and **Language checks / test**; the latter aggregates every language job and fails on skipped/cancelled dependencies.

The book job uploads the production output as a Pages artifact after publication checks. After all checks pass on `main`, the deployment job deploys that artifact with the built-in Pages token and OIDC. It needs no permission to push source commits. PRs validate and upload but do not deploy. Set **Settings → Pages → Source** to **GitHub Actions**, replacing the former `main /docs` deployment. The built-in workflow token cannot change this administrative setting; GitHub rejects that settings request with HTTP 403. For custom domains, update the Pages setting and `baseURL` in `website/hugo.toml` together. Confirm a successful deployment separately from a successful merge.

## Generate the standard library reference

`scripts/docgen` reads the checker's registry from pinned `stdlib/*.ms` source, including intrinsic receiver operations. The API's signatures, generic bounds, fields, cases, and operations have one source authority. Native calling conventions are compared with those declarations in integration tests; frontend initialization does not import the host runtime.

Generated module pages live in `documentation/standard-library/reference/`; `website/static/stdlib.md` and `stdlib.json` are downloads. The JSON schema is versioned and sorted. `website/static/llms.txt` points to the plain-text API. Special contextual calls are defined in [call rules](https://github.com/manuscript-lang/manuscript/blob/main/tooling/docgen/call-rules.md), which need review when checker calls change. Update source or generators, then run `make docs` and book checks. Never repair freshness by hand-editing generated output.
