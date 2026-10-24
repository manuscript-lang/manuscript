# Repository maintenance lessons

### Repository cleanup must remove duplicated work and layers

Decision: codebase cleanup should make the implementation easy to follow, with clear layer boundaries and one implementation of each shared behavior. Reorganizing files alone does not satisfy it: remove duplicated behavior and avoidable work before adding abstractions. Use the [simplify workflow](../skills/simplify/SKILL.md) to apply this preference while preserving behavior unless a change is requested.

Verified: the lasting lessons from the Go-era cleanup are source-level. Semantic lint should use resolved identities instead of re-lexing names. One shared executable-syntax traversal (including defaults, closures, and interpolation) should serve checking and tooling. Editor requests should reuse their source index and resolve receivers without building a full inspection document. A source-only CLI command should stop at a checked program rather than lowering.

Apply when: organizing crates, extracting helpers, or adding another frontend/tooling pass.
Evidence: [shared traversal](../crates/ms-syntax/src/visit.rs), [lint passes](../crates/ms-tooling/src/lint/mod.rs), [architecture](../documentation/contributing/architecture.md). The user message in "Organize repository layers" (chat `01a13b64-d01d-73d8-b318-7438b9ab402d`) establishes the preference.
Verify: identify the duplicate traversal, query, serialization, or forwarding path that disappears. Preserve source-level checking, default evaluation, module identity, and conformance; a smaller file tree alone is not evidence of simplification.

Verified: optimization works on a separate lowering view of checked source. Rewriting or removing AST nodes would break the node identities used by editor queries, lint, effects, and source maps. Parsing and resolution diagnostics travel with the syntax graph, including during recovery; folding a short-circuited expression must never let an invalid operand bypass checking.

Verified: a payload binder such as `error(NotFound)` can conceal a case name without a checking error. Advisory lint needs the checked identity before any sibling payload bindings enter scope, and each binder keeps its original position (rebased during partial parsing). Evidence: [binding lint](../crates/ms-tooling/src/lint/bindings.rs), [pattern lint](../crates/ms-tooling/src/lint/patterns.rs), [native binding versus separate payload handling](../tests/e2e/testdata/accept/pattern-binding-capture.ms).

### Documentation and site inputs keep their own homes

Verified: authored guides live in `documentation/`, site inputs in `website/`, and Pages output is built into ignored `.artifacts/book/` and deployed as an Actions artifact. Hugo mounts the shared root version and extension grammar as assets; parent-relative `readFile` calls did not resolve those inputs. The book and API reference come from the Rust docgen (`crates/ms-tooling/src/guide`), not a checked-in HTML tree.

Apply when: relocating documentation or site inputs, or changing the publication workflow.
Evidence: [site mounts](../website/hugo.toml), [publication checks](../tests/docs/publication.test.cjs), [architecture](../documentation/contributing/architecture.md).
Verify: run `make docs-check` and `make book-check`. Build `.artifacts/book/` with destination cleanup and verify the Pages artifact deployment; generated HTML is not a source commit.

### Pages deployment and Pages administration have different permissions

Verified: the built-in workflow token with Pages write permission can deploy artifacts, but GitHub rejected changing the existing site's build type through the settings REST endpoint with HTTP 403. Keep deployment on the standard configure/deploy actions; switching the repository's Pages source is an administrator action.

Decision: the user switched Pages to GitHub Actions and requested removal of obsolete Jekyll support. Publish Hugo output through the artifact workflow; no branch-publishing marker is needed. Historical workflow runs do not configure future publishing.

Apply when: migrating or repairing Pages publishing.
Evidence: [failed settings request](https://github.com/manuscript-lang/manuscript/actions/runs/38275457893/job/114902462365), [artifact deployment](../.github/workflows/cicd.yml), and [publishing instructions](../documentation/contributing/development.md).
Verify: inspect the actual deployment result, not just the book artifact or merged PR; confirm Pages source is GitHub Actions.
