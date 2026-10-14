# Repository maintenance lessons

### CI discovery failures must not become empty shards

Verified: a successful pipeline filter can hide a failed Go discovery command under POSIX `set -e`. `go test -list` also runs the end-to-end `TestMain`, which builds the CLI and can fail before listing tests. Capture Go output in checked assignments before filtering; reuse the complete package inventory and reject an empty split-package test inventory. An individual shard may legitimately select no tests.

Apply when: changing CI package discovery, test selection, or sharding.
Evidence: [shard runner](../scripts/ci-test.sh), [failure and inventory regressions](../scripts/repo-check/ci_test_test.go), and [end-to-end setup](../tests/e2e/harness_test.go).
Verify: run `go test ./scripts/repo-check -run '^TestCITest'`; injected discovery failures must exit nonzero, and four shards must select every test/package exactly once.

Verified: `go test -fuzz` can report success with no matching fuzz function after a package move. The compiler target now lives in `pkg/build`; its Makefile recipe checks successful exact-name discovery before fuzzing. [Fuzz target regressions](../scripts/repo-check/fuzz_test.go) reject missing targets and failed discovery even when partial output contains the expected name. When moving test packages, verify fuzz discovery and observe actual executions, not only the process exit code.

### Repository cleanup must remove duplicated work and layers

Decision: the user's codebase cleanup request includes simplifying the implementation as a whole; reorganizing files alone does not satisfy it. Consolidate duplicated behavior and remove avoidable work before adding abstraction layers.

Verified: source-only CLI commands stop at checked programs, while explicit application entry validation remains available without Go lowering. Semantic lint uses resolved identities instead of re-lexing names. Shared executable-syntax traversal includes defaults, closures, and interpolation; editor requests reuse their source index and resolve receivers without building an inspection document.

Apply when: organizing packages, extracting helpers, or adding another frontend/tooling pass.
Evidence: [shared traversal](../pkg/syntax/walk.go), [semantic lint](../pkg/tooling/lint_program.go), [CLI modes](../internal/cli/cli.go), [analysis entry regression](../pkg/build/metadata_test.go), and [default/list editor regressions](../pkg/tooling/lsp/defaults_test.go).
Verify: identify the duplicate traversal, query, serialization, or forwarding path that disappears. Preserve source-level checking, default evaluation, module identity, and native conformance; a smaller file tree alone is not evidence of simplification.

Verified: optimization uses a separate lowering view of checked source. Rewriting or removing AST nodes would break the pointer identities used by editor queries, lint, effects, and source maps. Parsing and resolution diagnostics travel with the AST graph, including during recovery; folding a short-circuited expression never permits an invalid operand to bypass checking. Evidence: [shared pipeline](../pkg/compiler/compiler.go), [source model regressions](../pkg/compiler/pipeline_test.go), and [native side-effect regression](../tests/e2e/testdata/accept/boolean-optimization.ms).

Verified: Go's test cache does not automatically track source built only by a subprocess. The native end-to-end harness imports the CLI implementation as a test dependency so changing CLI code invalidates its cached result. Evidence: [native harness dependency](../tests/e2e/e2e_test.go). For a final native run after command changes, use `go test -count=1 ./tests/e2e` with the pinned toolchain.

Verified: a payload binder such as `error(NotFound)` can conceal a case name
without a checking error. Advisory lint needs the checked identity before any
sibling payload bindings enter scope; the payload's own cases remain matchable
even when only its producing function was imported. Retain each binder's original
position and rebase it during partial parsing. Evidence: [checked name evidence](../pkg/checker/pattern_names.go),
[binding/alias/shadowing regressions](../pkg/tooling/pattern_lint_test.go),
[recovery positions](../pkg/parser/pattern_positions_test.go), and
[native binding versus separate payload handling](../tests/e2e/testdata/accept/pattern-binding-capture.ms).

### Package moves must preserve build identity and publication inputs

Verified: project manifest/import behavior now lives outside `compiler`. Its embedded implementation sources participate in native pins so future resolver changes invalidate build identity. Authored guides live in `documentation/`, site inputs in `website/`, and Pages output is built into ignored `.artifacts/book/` and deployed as an Actions artifact. Hugo mounts the shared root version and extension grammar as assets; parent-relative `readFile` calls did not resolve those inputs after the move.

Apply when: extracting a build-affecting package or relocating documentation/site inputs.
Evidence: [pin input bundles](../pkg/build/cache.go), [project source embedding](../pkg/project/identity.go), [site mounts](../website/hugo.toml), [publication checks](../tests/docs/publication.test.cjs), and [architecture](../documentation/contributing/architecture.md).
Verify: include moved behavior in implementation hashing and release workflow path filters; run `make docs-check`, `make book-check`, and `make dist-check`. Build `.artifacts/book/` with destination cleanup and verify the Pages artifact deployment; generated HTML is no longer a source commit.

Verified: reusable Go packages live in `pkg/`. Moving runtime code requires updating both the runtime import emitted by the compiler and the package queried by SDK payload discovery; ordinary package tests do not exercise payload discovery. Package-relative conformance fixture paths must also account for the additional directory level.
Evidence: [generated runtime import](../pkg/lower/generate.go), [SDK dependency discovery](../scripts/mktoolchain/main.go), [compiler fixtures](../pkg/build/compiler_test.go), and [layout and Go import migration](../documentation/contributing/architecture.md).
Verify: run native conformance and `make dist-check` after a package move, alongside the repository dependency/pin checks.

### Pages deployment and Pages administration have different permissions

Verified: the built-in workflow token with Pages write permission can deploy artifacts, but GitHub rejected changing the existing site's build type through the settings REST endpoint with HTTP 403. Keep deployment on the standard configure/deploy actions; switching the repository's Pages source is an administrator action.

Decision: the user switched Pages to GitHub Actions and requested removal of obsolete Jekyll support. Publish Hugo output through the artifact workflow; no branch-publishing marker is needed. Historical workflow runs do not configure future publishing.

Apply when: migrating or repairing Pages publishing.
Evidence: [failed settings request](https://github.com/manuscript-lang/manuscript/actions/runs/38275457893/job/114902462365), [artifact deployment](../.github/workflows/cicd.yml), and [publishing instructions](../documentation/contributing/development.md).
Verify: inspect the actual deployment result, not just the book artifact or merged PR; confirm Pages source is GitHub Actions.
