# Tooling and documentation lessons

### Repository cleanup must remove duplicated work and layers

Decision: the user's codebase cleanup request includes simplifying the implementation as a whole; reorganizing files alone does not satisfy it. Consolidate duplicated behavior and remove avoidable work before adding abstraction layers.

Verified: source-only CLI commands stop at checked programs, while explicit application entry validation remains available without Go lowering. Semantic lint uses resolved identities instead of re-lexing names. Shared executable-syntax traversal includes defaults, closures, and interpolation; editor requests reuse their source index and resolve receivers without building an inspection document.

Apply when: organizing packages, extracting helpers, or adding another frontend/tooling pass.
Evidence: [shared traversal](../syntax/walk.go), [semantic lint](../tooling/lint_program.go), [CLI modes](../internal/cli/cli.go), [analysis entry regression](../compiler/metadata_test.go), and [default/list editor regressions](../tooling/lsp/defaults_test.go).
Verify: identify the duplicate traversal, query, serialization, or forwarding path that disappears. Preserve source-level checking, default evaluation, module identity, and native conformance; a smaller file tree alone is not evidence of simplification.

Verified: Go's test cache does not automatically track source built only by a subprocess. The native end-to-end harness imports the CLI implementation as a test dependency so changing CLI code invalidates its cached result. Evidence: [native harness dependency](../tests/e2e/e2e_test.go). For a final native run after command changes, use `go test -count=1 ./tests/e2e` with the pinned toolchain.

### Package moves must preserve build identity and publication inputs

Verified: project manifest/import behavior now lives outside `compiler`. Its embedded implementation sources participate in native pins so future resolver changes invalidate build identity. Authored guides live in `documentation/`, site inputs in `website/`, and branch-based Pages output remains in `docs/`. Hugo mounts the shared root version and extension grammar as assets; parent-relative `readFile` calls did not resolve those inputs after the move.

Apply when: extracting a build-affecting package or relocating documentation/site inputs.
Evidence: [pin input bundles](../compiler/cache.go), [project source embedding](../project/identity.go), [site mounts](../website/hugo.toml), [publication checks](../tests/docs/publication.test.cjs), and [architecture](../documentation/contributing/architecture.md).
Verify: include moved behavior in implementation hashing and release workflow path filters; run `make docs-check`, `make book-check`, and `make dist-check`. Regenerate `docs/` with destination cleanup and retain the existing Pages output path unless deployment is explicitly migrated.

### Editor recovery must preserve delimiter continuations

Verified: strict parsing accepts multiline parameters, but declaration recovery previously split their column-zero closing delimiters into separate chunks whenever any declaration was malformed. This discarded valid functions and their parameter scopes in the LSP. Recovery now consults the lexer for continuation boundaries while fresh declarations still synchronize after an unmatched opener. Completion snapshots also need a match arm, rather than an ordinary statement, to repair an unfinished `match` suite.

Apply when: changing partial parsing, declaration synchronization, or completion snapshot repair.
Evidence: [layout rules](../documentation/core-language/basics/grammar.md#layout-tokens); [recovery regressions](../parser/partial_test.go); [parameter navigation regression](../tooling/lsp/analysis_test.go); [completion regressions](../tooling/lsp/completion_test.go).
Verify: multiline function parameters retain their original LF/CRLF positions, navigation, and completion when a different declaration is incomplete; an unfinished match does not erase completion in the enclosing function.

### Standard declarations are source that tools must navigate

Decision: the user asked to keep standard type definitions in Manuscript so editor tooling can use them. Verified architecture: `stdlib/*.ms` supplies public schemas and signatures; `bindings.json` maps identities to native dispatch. Generated documentation and navigation consume this source-backed contract.

Verified: navigation must continue after the first jump into a standard declaration. Register the virtual document scheme with the language client and retain the standard loader's resolved type references for tooling; reparsing library signatures as executable workspace modules loses their checked context. Keep virtual documents immutable and outside workspace source overlays.

Apply when: adding standard APIs, changing their signatures, or extending hover/navigation/documentation.
Evidence: [source-definition request](codex://threads/01a12ce1-c9ff-70e4-bb2c-51749183e03b); [declaration ownership](../stdlib/README.md); [embedded sources](../stdlib/sources.go); [documentation generator](../scripts/docgen/main.go).
Evidence for continued navigation: [standard loader](../checker/standard.go), [virtual document analysis](../tooling/lsp/analysis.go), [navigation regression tests](../tooling/lsp/features_test.go), [read-only session test](../tooling/lsp/server_test.go), and [client restart test](../extensions/vscode/tests/extension.test.js).
Verify: native calling signatures agree with the declarations, editor definitions reach the declaration and can follow imports and signature types from there, and generated references pass the existing freshness check. Update the source or generator when output changes.

Decision: the string utility module is `@std/string.ms`, matching the intrinsic `String` type. The user requested this spelling when expanding built-in parity. Receiver operations need no module import; standalone string functions use this canonical module. Evidence: [declarations](../stdlib/string.ms), [native bindings](../stdlib/bindings.json), and [data package guide](../documentation/standard-library/packages/data.md). When renaming a module, verify imports, native dispatch identities, virtual editor documents, and generated reference paths together.

### Teach a runnable path before formal reference

Decision: simplify the reading path, explain one concept at a time, and give each exact rule one home. A basic destructuring example should not require the reader to understand parallel work and error propagation. The docs revamp requested simpler explanations without losing precise semantics.

Apply when: adding tutorials, revising design chapters, or explaining new syntax.
Evidence: [documentation simplification discussion](codex://threads/01a12bf3-438d-7c72-a846-7443cea58e3a); [clarity and duplication request](codex://threads/01a12ae0-579b-7890-89d4-c0091474a2f5); [learn index](../documentation/learn/_index.md).
Verify: run the displayed source and commands with the stated prerequisites; check that the reading path introduces dependencies before using them. Build the book with its current strict checks and link to canonical rules instead of repeating them.

### User tooling must work in the shipped binary

Decision: documentation generation was requested as an `ms` subcommand for users, rather than only a repository generator. Native builds were subsequently requested to work from a single binary without separately installing Go, with CGO excluded. This establishes a delivery boundary for user-facing tooling: test the command from the user's installation context.

Apply when: adding CLI tooling or making claims about installation requirements.
Evidence: [ms doc request](codex://threads/01a12d4a-0182-7672-aa00-53f2bdfde033); [native build contract](../documentation/compiler/builds/reproducibility.md); [payload construction](../scripts/mktoolchain/main.go); [standalone distribution checks](../scripts/distcheck/main.go).
Verify: exercise a copied binary outside the checkout with empty caches, no Go on PATH, and package downloads disabled. Include ordinary/debug builds and profiling so the reduced payload covers emitted runtime references. Confirm actual external prerequisites for tools such as Delve separately; do not generalize one command's prerequisites to all tooling.

### Polish the documentation design without expanding its prose

Decision: for the documentation redesign, the user selected Tailwind CSS and Vercel as visual references and explicitly asked, “don't just randomly keep adding text.” Favor consistent navigation, typography, spacing, and reading layouts; preserve authored explanations rather than introducing promotional copy to fill the page.

Decision: use `ms` as the documentation logo, including the header and favicon, rather than a single `m`. Check the mark at desktop and mobile sizes when changing [branding](../website/layouts/_partials/docs/brand.html) or the [favicon](../website/static/favicon.svg).

Apply when: redesigning the documentation shell or overview, or extending its visual system.
Evidence: the user's documentation redesign correction; [Tailwind docs](https://tailwindcss.com/docs/installation/using-vite); [Vercel docs](https://vercel.com/docs); [site-owned visual system](../website/assets/_custom.scss); [overview presentation](../website/layouts/_shortcodes/docs-home.html).
Decision: the user requested reuse of VS Code highlighting code where possible. The docs use the extension's [TextMate grammar](../extensions/vscode/syntaxes/manuscript.tmLanguage.json) as their single source of lexical rules, through a small [browser adapter](../website/assets/manuscript-highlight.js). Keep language patterns in the shared grammar instead of adding a separate keyword list for the website.

Decision: present API classifications as human-readable badges beside symbol headings, instead of exposing compiler labels such as `Kind: fn.` as prose. The [generator](../tooling/docgen/documentation.go) keeps portable Markdown readable and raw JSON kinds stable; the [heading renderer](../website/layouts/_markup/render-heading.html) adds badges without changing symbol anchors or table-of-contents labels. Check [presentation contracts](../tooling/docgen/documentation_test.go) and rendered pages when changing this metadata.

Decision: show API excerpts in regular Manuscript declaration syntax, rather than checker dumps such as `DnsRecord: DnsRecord`, `field kind: String`, or `operation receive: fn(...)->...`. Generate fields, cases, methods, and generic bounds from the [source declarations](../checker/documentation_syntax.go), omitting implementation bodies. Compiler-bound calls without an ordinary declaration link to their special call rules rather than displaying `<unknown>` as a type. Verify the [declaration syntax checks](../checker/documentation_test.go), CLI output, and published pages together; keep the machine-readable JSON contract stable.

Verified: styling a code container did not highlight Manuscript examples fenced as `text`. Explicit `manuscript` fences now use the shared grammar, with [tokenization checks](../tests/docs/highlighting.test.cjs). The [documentation generator](../tooling/docgen/documentation.go) emits the same language label so regenerated API pages retain highlighting.

Verify: compare authored Markdown with the base branch, keep semantic changes out of visual work, check desktop and mobile reading pages, and run the strict Hugo build with a repository URL prefix. Verify actual token colors in light and dark mode, unchanged copied text, and plain terminal output. Regenerate `docs/` from the current sources; never resolve generated-page conflicts by retaining stale output.

### Source freshness does not establish published freshness

Verified: after the concurrency simplification, source declarations and generated Markdown were current while the checked-in website still exposed retired bounds and a removed module route. The user found this in the API reference. A source-generation check alone cannot verify the HTML, downloadable schemas, or search index that readers receive.

Apply when: removing or renaming public language/API surface, or reporting a documentation update complete.
Evidence: the user's follow-up to [the concurrency change](https://github.com/manuscript-lang/manuscript/pull/24); [publication checks](../tests/docs/publication.test.cjs); [publishing workflow](../.github/workflows/cicd.yml).
Verify: regenerate both reference sources and the website with destination cleanup; compare shipped schema downloads against current generated sources, reject obsolete module routes, and search rendered pages and search data for retired terminology. Confirm publication separately from a successful source merge. Historical review text must not reintroduce syntax the user explicitly requested removing.

### Standalone runtime imports share one alias namespace

Verified: standalone generation merges runtime declarations and deduplicates imports by import path. Inconsistent aliases for the same Go package can pass ordinary runtime package compilation while breaking every emitted application. Platform helper packages also need inclusion in the standalone dependency bundle; embedding the main runtime sources alone does not carry imported repository packages.

Apply when: adding native runtime implementation files or platform adapters.
Evidence: [standalone merger](../compiler/build.go), [import-alias regression check](../compiler/library_test.go), [native dependency bundle](../native_bundle.go), and [platform bridge](../internal/hostos/hostos.go).
Verify: `TestBundledRuntimeImportAliasesAgree`, source-to-native CLI tests, and the packaged binary check with an empty cache and no system Go.

Verified: native compilation must build the temporary module (`go build .`) rather than an absolute source filename. A filename build can give the main package the synthetic `command-line-arguments` identity and reject bundled internal imports when path canonicalization differs, as on macOS temporary paths. [Native build regression](../compiler/library_test.go) exercises a symlinked temporary root; [module build](../compiler/build.go) preserves the dependency namespace.
