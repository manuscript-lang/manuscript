# Tooling and documentation lessons

### Readable formatting needs paragraphs while retaining inline guards

Decision: the user's formatter request keeps inline `if` bodies and introduces
natural reading boundaries around declarations, guard sections, substantial
control flow, and indented match arms. This also requires wrapping complex
expressions; paragraph breaks alone leave dense calls and conditions unreadable.
Do not expand inline bodies to create readability or guess business stages from
adjacent call names.

Apply when: changing source formatting or adding layout heuristics.
Evidence: [formatting policy](../documentation/developer-tooling/implementation.md#linting-and-formatting),
[syntax boundaries](../pkg/tooling/format_paragraphs.go),
[expression layout](../pkg/tooling/format_layout.go), and
[layout regressions](../pkg/tooling/format_layout_test.go).
Verify: bindings and consecutive guards stay together; subsequent work starts a
paragraph; branch families and leading comments remain attached; LF/CRLF output
preserves literal spellings and is identical after a second format. Added grouping
must preserve the entire parsed syntax tree, especially inline callback return
boundaries and mixed-precedence conditions. Moving a callback argument must move
its suite indentation too.

### Native build levels need artifact evidence

Verified: Go omits recorded linker flags from build information when `-trimpath` is enabled. Check symbol/DWARF sections and executable size to verify stripping, rather than treating a missing recorded `-ldflags` value as a build failure. Both Debug and optimized RelWithDebInfo retain local source paths, so both need source-root-sensitive cache identities.

Apply when: changing native optimization, symbol settings, or build caches.
Evidence: [build level contract](../documentation/compiler/builds/build-levels.md), [native flags](../pkg/compiler/build_type.go), [cache identity](../pkg/compiler/cache.go), and [native artifact checks](../pkg/compiler/build_type_test.go).
Verify: build all four levels, execute and restore each artifact, check native optimization settings and debug sections, and compare stripped sizes with RelWithDebInfo.

### Repository cleanup must remove duplicated work and layers

Decision: the user's codebase cleanup request includes simplifying the implementation as a whole; reorganizing files alone does not satisfy it. Consolidate duplicated behavior and remove avoidable work before adding abstraction layers.

Verified: source-only CLI commands stop at checked programs, while explicit application entry validation remains available without Go lowering. Semantic lint uses resolved identities instead of re-lexing names. Shared executable-syntax traversal includes defaults, closures, and interpolation; editor requests reuse their source index and resolve receivers without building an inspection document.

Apply when: organizing packages, extracting helpers, or adding another frontend/tooling pass.
Evidence: [shared traversal](../pkg/syntax/walk.go), [semantic lint](../pkg/tooling/lint_program.go), [CLI modes](../internal/cli/cli.go), [analysis entry regression](../pkg/compiler/metadata_test.go), and [default/list editor regressions](../pkg/tooling/lsp/defaults_test.go).
Verify: identify the duplicate traversal, query, serialization, or forwarding path that disappears. Preserve source-level checking, default evaluation, module identity, and native conformance; a smaller file tree alone is not evidence of simplification.

Verified: optimization uses a separate lowering view of checked source. Rewriting or removing AST nodes would break the pointer identities used by editor queries, lint, effects, and source maps. Parsing and resolution diagnostics travel with the AST graph, including during recovery; folding a short-circuited expression never permits an invalid operand to bypass checking. Evidence: [shared pipeline](../pkg/compiler/compiler.go), [source model regressions](../pkg/compiler/pipeline_test.go), and [native side-effect regression](../tests/e2e/testdata/accept/boolean-optimization.ms).

Verified: Go's test cache does not automatically track source built only by a subprocess. The native end-to-end harness imports the CLI implementation as a test dependency so changing CLI code invalidates its cached result. Evidence: [native harness dependency](../tests/e2e/e2e_test.go). For a final native run after command changes, use `go test -count=1 ./tests/e2e` with the pinned toolchain.

### Package moves must preserve build identity and publication inputs

Verified: project manifest/import behavior now lives outside `compiler`. Its embedded implementation sources participate in native pins so future resolver changes invalidate build identity. Authored guides live in `documentation/`, site inputs in `website/`, and Pages output is built into ignored `.artifacts/book/` and deployed as an Actions artifact. Hugo mounts the shared root version and extension grammar as assets; parent-relative `readFile` calls did not resolve those inputs after the move.

Apply when: extracting a build-affecting package or relocating documentation/site inputs.
Evidence: [pin input bundles](../pkg/compiler/cache.go), [project source embedding](../pkg/project/identity.go), [site mounts](../website/hugo.toml), [publication checks](../tests/docs/publication.test.cjs), and [architecture](../documentation/contributing/architecture.md).
Verify: include moved behavior in implementation hashing and release workflow path filters; run `make docs-check`, `make book-check`, and `make dist-check`. Build `.artifacts/book/` with destination cleanup and verify the Pages artifact deployment; generated HTML is no longer a source commit.

Verified: reusable Go packages live in `pkg/`. Moving runtime code requires updating both the runtime import emitted by the compiler and the package queried by SDK payload discovery; ordinary package tests do not exercise payload discovery. Package-relative conformance fixture paths must also account for the additional directory level.
Evidence: [generated runtime import](../pkg/compiler/generate.go), [SDK dependency discovery](../scripts/mktoolchain/main.go), [compiler fixtures](../pkg/compiler/compiler_test.go), and [layout and Go import migration](../documentation/contributing/architecture.md).
Verify: run native conformance and `make dist-check` after a package move, alongside the repository dependency/pin checks.

### Native omissions are declared and preserved across interface dispatch

Verified: native Optional defaults are written as `= none` in the standard function, method, or constructor-field declaration. Constructor omission follows that source metadata. Application implementations inherit standard interface default permissions and receive a concrete `none`, while native compositions pass `some(n)` through source-defined streams. Inferring default permission merely from a field's name would create a second schema; passing raw integers through an Optional interface would break source implementations.

Apply when: adding native defaults, changing source/native signatures, or implementing stream compositions.
Evidence: [standard source checks](../pkg/checker/standard.go), [constructor/ABI regressions](../pkg/checker/stdlib_revamp_test.go), [native emission](../pkg/compiler/lower_functions.go), and [compiled stream boundary](../tests/e2e/testdata/accept/stdlib-revamp.ms).
Verify: inspect the generated declaration for `= none`; omit a limit through an application-defined ReadStream and match `none`; run read_line over that implementation and match its supplied `some(1)`. Migrate embedded source fixtures in native debugger tests too: an invalid constructor argument can leave a DAP launch waiting for initialization instead of surfacing its build diagnostic.

### Editor recovery must preserve delimiter continuations

Verified: strict parsing accepts multiline parameters, but declaration recovery previously split their column-zero closing delimiters into separate chunks whenever any declaration was malformed. This discarded valid functions and their parameter scopes in the LSP. Recovery now consults the lexer for continuation boundaries while fresh declarations still synchronize after an unmatched opener. Completion snapshots also need a match arm, rather than an ordinary statement, to repair an unfinished `match` suite.

Apply when: changing partial parsing, declaration synchronization, or completion snapshot repair.
Evidence: [layout rules](../documentation/core-language/basics/grammar.md#layout-tokens); [recovery regressions](../pkg/parser/partial_test.go); [parameter navigation regression](../pkg/tooling/lsp/analysis_test.go); [completion regressions](../pkg/tooling/lsp/completion_test.go).
Verify: multiline function parameters retain their original LF/CRLF positions, navigation, and completion when a different declaration is incomplete; an unfinished match does not erase completion in the enclosing function.

### Standard declarations are source that tools must navigate

Decision: the user asked to keep standard type definitions in Manuscript so editor tooling can use them. Verified architecture: `pkg/stdlib/*.ms` supplies public schemas and signatures; `bindings.json` maps identities to native dispatch. Generated documentation and navigation consume this source-backed contract.

Verified: bundled modules containing bodies use ordinary Manuscript parsing, checking, and lowering. Recheck reachable source implementations in each program rather than mutating shared registry symbols. Publish only module-owned exports: a checked module's name table also contains imported symbols and prelude types, which must not become new exports. Native declarations retain empty bodies and ABI bindings; all standard modules use ordinary parsing. Evidence: [standard source loader](../pkg/checker/standard.go), [reachability and visibility regressions](../pkg/compiler/source_stdlib_test.go), and [source navigation](../pkg/tooling/navigation_test.go).

Verified: navigation must continue after the first jump into a standard declaration. Register the virtual document scheme with the language client and retain the standard loader's resolved type references for tooling; reparsing library signatures as executable workspace modules loses their checked context. Keep virtual documents immutable and outside workspace source overlays.

Verified: standard source syntax must also pass ordinary `parser.Parse` and formatting. A permissive library-only parser concealed missing bodies, mixed receiver signatures, and field-default errors. The user requires ordinary empty functions with colon headers, including receiver functions, and empty opaque schemas with colons. Do not replace these with a `native` modifier. Binding authorization belongs to checking. Disk editor documents reuse pinned bindings only for exact source matches, while syntax validity is independently tested. Both repo-check modes validate working-tree stdlib sources through the strict frontend and return a positioned error before checker initialization, so `make check`, `make repo-check`, and CI verification reject invalid syntax directly. Evidence: [all-source parsing and formatting](../pkg/stdlib/sources_test.go), [empty-function grammar boundaries](../pkg/parser/empty_declarations_test.go), [disk document checks](../pkg/tooling/lsp/standard_test.go), and [syntax gate regressions](../scripts/repo-check/main_test.go).

Apply when: adding standard APIs, changing their signatures, or extending hover/navigation/documentation.
Evidence: [source-definition request](codex://threads/01a12ce1-c9ff-70e4-bb2c-51749183e03b); [declaration ownership](../pkg/stdlib/README.md); [embedded sources](../pkg/stdlib/sources.go); [documentation generator](../scripts/docgen/main.go).
Evidence for continued navigation: [standard loader](../pkg/checker/standard.go), [virtual document analysis](../pkg/tooling/lsp/analysis.go), [navigation regression tests](../pkg/tooling/lsp/features_test.go), [read-only session test](../pkg/tooling/lsp/server_test.go), and [client restart test](../extensions/vscode/tests/extension.test.js).
Verify: native calling signatures agree with the declarations, editor definitions reach the declaration and can follow imports and signature types from there, and generated references pass the existing freshness check. Update the source or generator when output changes.

Decision: the string utility module is `@std/string.ms`, matching the intrinsic `String` type. The user requested this spelling when expanding built-in parity. Receiver operations need no module import; standalone string functions use this canonical module. Evidence: [declarations](../pkg/stdlib/string.ms), [native bindings](../pkg/stdlib/bindings.json), and [data package guide](../documentation/standard-library/packages/data.md). When renaming a module, verify imports, native dispatch identities, virtual editor documents, and generated reference paths together.

### Keep CLI and HTTP documentation with their packages

Decision: the user explicitly removed the “Application hosts” section. CLI entry/accessor/shutdown contracts belong in the CLI package guide, and HTTP request/shutdown contracts belong in the HTTP package guide. Do not recreate a separate host category in the standard-library navigation.

Apply when: organizing the standard-library guide or adding application-entry documentation.
Evidence: [standard-library navigation](../documentation/standard-library/_index.md), [CLI guide](../documentation/standard-library/packages/cli.md), and [HTTP guide](../documentation/standard-library/packages/http.md).
Verify: build the book with destination cleanup and confirm there is no standard-library/hosts route or sidebar section; existing entry and request links resolve to package pages.

### Teach a runnable path before formal reference

Decision: public documentation should focus on Manuscript and what readers can build, without introductions framed around other languages. Use practical, example-first progression through variables, collections, functions, types, errors, and modules; keep indexes short and link to the exact rules. Clearly separate intentional rejection examples from the usual runnable path. Simplify the reading path, explain one concept at a time, and give each exact rule one home. A basic destructuring example should not require the reader to understand task-group work and error propagation. The docs revamp requested simpler explanations without losing precise semantics.

Apply when: adding tutorials, revising design chapters, or explaining new syntax.
Evidence: [documentation simplification discussion](codex://threads/01a12bf3-438d-7c72-a846-7443cea58e3a); [clarity and duplication request](codex://threads/01a12ae0-579b-7890-89d4-c0091474a2f5); [learn index](../documentation/learn/_index.md).
Verify: run the displayed source and commands with the stated prerequisites; check that the reading path introduces dependencies before using them. Build the book with its current strict checks and link to canonical rules instead of repeating them.

Verified: a `manuscript-example` annotation alone does not put a chapter into the executable example suite. The harness discovers introductory tutorials and explicitly listed guides; the logging guide needed an inventory entry before its annotated stdout example was checked or run. See [the example inventory](../tests/examples/examples_test.go) and [the logging example](../documentation/standard-library/packages/tooling.md). When adding complete examples outside the introductory chapters, confirm that their file appears in the harness and run its named subtest with `MANUSCRIPT_EXAMPLES_NATIVE=1`.

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

Decision: present API classifications as human-readable badges beside symbol headings, instead of exposing compiler labels such as `Kind: fn.` as prose. The [generator](../pkg/tooling/docgen/documentation.go) keeps portable Markdown readable and raw JSON kinds stable; the [heading renderer](../website/layouts/_markup/render-heading.html) adds badges without changing symbol anchors or table-of-contents labels. Check [presentation contracts](../pkg/tooling/docgen/documentation_test.go) and rendered pages when changing this metadata.

Decision: show API excerpts in regular Manuscript declaration syntax, rather than checker dumps such as `DnsRecord: DnsRecord`, `field kind: String`, or `operation receive: fn(...)->...`. Generate fields, cases, methods, and generic bounds from the [source declarations](../pkg/checker/documentation_syntax.go), omitting implementation bodies. Compiler-bound calls without an ordinary declaration link to their special call rules rather than displaying `<unknown>` as a type. Verify the [declaration syntax checks](../pkg/checker/documentation_test.go), CLI output, and published pages together; keep the machine-readable JSON contract stable.

Verified: styling a code container did not highlight Manuscript examples fenced as `text`. Explicit `manuscript` fences now use the shared grammar, with [tokenization checks](../tests/docs/highlighting.test.cjs). The [documentation generator](../pkg/tooling/docgen/documentation.go) emits the same language label so regenerated API pages retain highlighting.

Verify: compare authored Markdown with the base branch, keep semantic changes out of visual work, check desktop and mobile reading pages, and run the strict Hugo build with a repository URL prefix. Verify actual token colors in light and dark mode, unchanged copied text, and plain terminal output. Build `.artifacts/book/` from the current sources; never resolve generated-page conflicts by retaining stale output.

### Source freshness does not establish published freshness

Verified: after the concurrency simplification, source declarations and generated Markdown were current while the checked-in website still exposed retired bounds and a removed module route. The user found this in the API reference. A source-generation check alone cannot verify the HTML, downloadable schemas, or search index that readers receive.

Apply when: removing or renaming public language/API surface, or reporting a documentation update complete.
Evidence: the user's follow-up to [the concurrency change](https://github.com/manuscript-lang/manuscript/pull/24); [publication checks](../tests/docs/publication.test.cjs); [publishing workflow](../.github/workflows/cicd.yml).
Verify: regenerate both reference sources and the website with destination cleanup; compare shipped schema downloads against current generated sources, reject obsolete module routes, and search rendered pages and search data for retired terminology. Confirm publication separately from a successful source merge. Historical review text must not reintroduce syntax the user explicitly requested removing.

### Standalone runtime imports share one alias namespace

Verified: native builds keep the embedded runtime in its own package; merging it into the application forced Go to recompile host services after every source edit. Writing the 15 MB dependency bundle into a fresh directory took about as long as compiling and linking, and changing directories defeated package-cache reuse for Debug; a shared content-addressed workspace removed both. After that, the go command's package loading cost about 100 ms per edit, so rebuilds replay the traced compile/link of `package main` and fall back to `go build` on any mismatch. Linking was then the floor: about 230 ms Release, dominated by loading 108 MB of package archives, half of them `net/http`, `crypto/tls`, and gopsutil. Programs that import no network, system, or process module now link an `ms_lean` runtime without them (about 150 ms). Values of those modules' types only originate from their own functions, which makes module imports a sound selection rule. Keep heavy native dependencies in `!ms_lean` files, list their modules in the compiler's full-runtime set, and let the lean inventory test catch omissions. Per-process costs matter at this scale: loading standard declarations in `checker` package init cost 33 ms on every `ms` invocation, and garbage collection was about a third of that; load them on first use, overlap the pin with checking, and keep the language server on Go's default GC target. Keep single-file merging confined to `emit`. A separately compiled runtime also changes Delve type names, so debugger watches use Delve's `.(data)` rather than hard-coded `main.Record` assertions.
Evidence: [native assembly](../pkg/compiler/build.go), [shared workspace](../pkg/compiler/workspace.go), [command replay](../pkg/compiler/replay.go), [runtime variants](../pkg/compiler/variant.go), [lean stubs](../pkg/runtime/lean.go), [cache boundaries](../documentation/compiler/builds/incremental-compilation.md), [standalone artifact invalidation](../tests/e2e/run_cache_test.go), and [native debugger checks](../extensions/vscode/tests/debug-adapter.test.js).
Verify: run native conformance and the native DAP test; compare both unchanged runs and edited-source builds with warm Go caches for Release and Debug. Unchanged runs exercise executable caching and do not establish runtime package reuse after edits. Check that replay profiles exist under the workspace and that a missing archive or tool falls back to `go build`.

Verified: standalone generation merges runtime declarations and deduplicates imports by import path. Inconsistent aliases for the same Go package can pass ordinary runtime package compilation while breaking every emitted application. Platform helper packages also need inclusion in the standalone dependency bundle; embedding the main runtime sources alone does not carry imported repository packages.

Apply when: adding native runtime implementation files or platform adapters.
Evidence: [standalone merger](../pkg/compiler/build.go), [import-alias regression check](../pkg/compiler/library_test.go), [native dependency bundle](../native_bundle.go), and [platform bridge](../internal/hostos/hostos.go).
Verify: `TestBundledRuntimeImportAliasesAgree`, source-to-native CLI tests, and the packaged binary check with an empty cache and no system Go.

Verified: native compilation must build the temporary module (`go build .`) rather than an absolute source filename. A filename build can give the main package the synthetic `command-line-arguments` identity and reject bundled internal imports when path canonicalization differs, as on macOS temporary paths. [Native build regression](../pkg/compiler/library_test.go) exercises a symlinked temporary root; [module build](../pkg/compiler/build.go) preserves the dependency namespace.

### Frontend independence retains runtime contract checks

Decision: native receiver signatures belong directly on the standard type or intrinsic interface. Do not duplicate them as private free functions. Native bindings identify implementations and any method-specific receiver requirements; the checker resolves requirements against checked standard types without importing the host runtime.

Verified: shared decimal literal rules and runtime receiver identities live in lightweight internal packages; the checker cannot import runtime/host dependencies under the repository policy. Native signature comparisons validate receiver types, parameters, results, generic variables, bounds, and binding coverage directly against receiver declarations, including deliberate mismatch regressions.

Apply when: adding standard operations or moving runtime code.
Evidence: [source receiver constraints](../pkg/checker/native_members.go), [ABI tests](../pkg/checker/library_test.go), [dependency and bundle policy](../scripts/repo-check/policy.json), and [policy checks](../scripts/repo-check/main.go).
Verify: run `make verify` and native conformance. New bundled internal sources must enter the dependency bundle and implementation identity.

### Pages deployment and Pages administration have different permissions

Verified: the built-in workflow token with Pages write permission can deploy artifacts, but GitHub rejected changing the existing site's build type through the settings REST endpoint with HTTP 403. Keep deployment on the standard configure/deploy actions; switching the repository's Pages source is an administrator action.

Decision: the user switched Pages to GitHub Actions and requested removal of obsolete Jekyll support. Publish Hugo output through the artifact workflow; no branch-publishing marker is needed. Historical workflow runs do not configure future publishing.

Apply when: migrating or repairing Pages publishing.
Evidence: [failed settings request](https://github.com/manuscript-lang/manuscript/actions/runs/38275457893/job/114902462365), [artifact deployment](../.github/workflows/cicd.yml), and [publishing instructions](../documentation/contributing/development.md).
Verify: inspect the actual deployment result, not just the book artifact or merged PR; confirm Pages source is GitHub Actions.
