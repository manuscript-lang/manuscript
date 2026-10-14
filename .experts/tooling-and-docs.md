# Tooling and documentation lessons

### Readable formatting needs paragraphs while retaining inline guards

Decision: the user's formatter request keeps inline `if` bodies and introduces
natural reading boundaries around declarations, guard sections, substantial
control flow. Later feedback in [issue #102](https://github.com/manuscript-lang/manuscript/issues/102)
requires preserving authored spacing between match arms and keeping short lists
and callback signatures compact. This also requires wrapping complex
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
its suite indentation too. A later call in a chain must budget its own arguments;
a callback body must not consume the parameter signature's width budget.
The [compact golden fixture](../pkg/tooling/testdata/format/compact.golden.ms)
exercises these boundaries alongside comments and literal spellings.

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
Verify: native calling signatures agree with the declarations, editor definitions reach the declaration and can follow imports and signature types from there, and generated references pass the existing freshness check. Update the source or generator when output changes. Regenerate from combined source after integration: adding List/Map to the prelude makes their receiver additions appear in the prelude reference as well as the collections reference. Conflict-free merges can still leave generated prelude/download artifacts stale; post-merge docs-check caught this for #262/#269, and combined generation restores those methods. Member-description extraction changes also require combined regeneration, even when merged signature strings remain current.

Decision: the string utility module is `@std/string.ms`, matching the intrinsic `String` type. The user requested this spelling when expanding built-in parity. Receiver operations need no module import; standalone string functions use this canonical module. Evidence: [declarations](../pkg/stdlib/string.ms), [native bindings](../pkg/stdlib/bindings.json), and [data package guide](../documentation/standard-library/data.md). When renaming a module, verify imports, native dispatch identities, virtual editor documents, and generated reference paths together.

### Keep CLI and HTTP documentation with their packages

Decision: the user explicitly removed the “Application hosts” section. CLI entry/accessor/shutdown contracts belong in the CLI package guide, and HTTP request/shutdown contracts belong in the HTTP package guide. Do not recreate a separate host category in the standard-library navigation.

Apply when: organizing the standard-library guide or adding application-entry documentation.
Evidence: [standard-library navigation](../documentation/standard-library/_index.md), [CLI guide](../documentation/standard-library/cli.md), and [HTTP guide](../documentation/standard-library/http.md).
Verify: build the book with destination cleanup and confirm there is no standard-library/hosts route or sidebar section; existing entry and request links resolve to package pages.

### Teach a runnable path before formal reference

Decision: public documentation should focus on Manuscript and what readers can build. Remove comparisons with other languages, coverage maps, implementation inventories, and review bookkeeping. Keep one getting-started guide; modules, references, and cleanup belong in the language reference, application builds in developer tools, and compiler internals in contributor documentation. Use clear topic names and keep the sidebar, overview, and reading order consistent. Teach basics, functions, types, control flow, errors, modules, and resource management before library services and concurrent work. Library topics should be directly reachable; group scheduling, sharing, synchronization, and queues with concurrent work. State availability and limits beside the affected feature. Use practical, example-first progression through variables, collections, functions, types, errors, and modules; keep indexes short and link to exact rules. Clearly separate intentional rejection examples from the usual runnable path. A basic destructuring example should not require task-group work and error propagation.

Apply when: adding tutorials, revising design chapters, or explaining new syntax.
Evidence: [documentation simplification discussion](codex://threads/01a12bf3-438d-7c72-a846-7443cea58e3a); [clarity and duplication request](codex://threads/01a12ae0-579b-7890-89d4-c0091474a2f5); [learn index](../documentation/learn/_index.md).
Verify: run the displayed source and commands with the stated prerequisites; check that the reading path introduces dependencies before using them. Sidebar and previous/next links use the same [navigation order](../website/data/navigation.toml); the [publication checks](../tests/docs/publication.test.cjs) compare their rendered order. Build the book with its current strict checks and link to canonical rules instead of repeating them.

Verified: a `manuscript-example` annotation alone does not put a chapter into the executable example suite. The harness discovers introductory tutorials and explicitly listed guides; the logging guide needed an inventory entry before its annotated stdout example was checked or run. See [the example inventory](../tests/examples/examples_test.go) and [the logging example](../documentation/standard-library/packages/tooling.md). When adding complete examples outside the introductory chapters, confirm that their file appears in the harness and run its named subtest with `MANUSCRIPT_EXAMPLES_NATIVE=1`.

Task recipes must also preserve I/O failure: matching a failed stdout write and returning success hides an undelivered result. [Common tasks](../documentation/learn/common-tasks.md) forwards write/flush errors to a nonzero entry status. The same [example harness](../tests/examples/examples_test.go) supplies isolated files, stdin, and loopback HTTP plus additional expected-failure cases; type checking alone cannot establish the displayed output, EOF handling, or failure status. See [annotation fields and native execution](../documentation/contributing/development.md#conformance-and-coverage).

### User tooling must work in the shipped binary

Decision: documentation generation was requested as an `ms` subcommand for users, rather than only a repository generator. Native builds were subsequently requested to work from a single binary without separately installing Go, with CGO excluded. The later requirement makes the bundled toolchain mandatory: no external override, PATH fallback, or ambient Go configuration may select another tool. OS-specific prerequisites such as Apple debugserver remain permitted. This establishes a delivery boundary for user-facing tooling: test the command from the user's installation context.

Apply when: adding CLI tooling or making claims about installation requirements.
Evidence: [ms doc request](codex://threads/01a12d4a-0182-7672-aa00-53f2bdfde033); [native build contract](../documentation/developer-tooling/builds/reproducibility.md); [payload construction](../scripts/mktoolchain/main.go); [standalone distribution checks](../scripts/distcheck/main.go).
Verify: exercise a copied binary outside the checkout with empty caches, no Go on PATH, and package downloads disabled. Include ordinary/debug builds and profiling so the reduced payload covers emitted runtime references. Confirm actual debugger backend prerequisites separately; do not generalize one platform’s prerequisites to all tooling.

Verified: embedding Delve uses its public `service`/`pkg` APIs, not restricted
`internal` imports. The pinned backend still needs Apple debugserver on macOS,
and Windows ARM64 requires `exp.winarm64`; neither justifies enabling CGO for
all distributions. DAP uses an owned private pipe and joins the read loop on
shutdown: upstream’s asynchronous server startup can race an early stop. Closing
editor input lets the service reap targets before exit, especially on Windows
where killing the adapter process immediately bypasses cleanup.
Evidence: [embedded services](../internal/debugger/debugger.go),
[shutdown race regressions](../internal/debugger/debugger_test.go),
[copied-binary debugger checks](../scripts/distcheck/debugger.go), and
[platform contract](../documentation/developer-tooling/debugging/debugger-integration.md).

Verified: inspection's general statement list includes default-argument callback
bodies before the containing function's body; header spans do not bound callable
bodies. Function breakpoints must use the explicit callable `entry`, derived from
the checked body's first statement. Evidence and verification:
[inspection regression](../pkg/tooling/inspect_entry_test.go) and
[native default-callback breakpoint](../tests/e2e/debug_script_test.go).

Verified: closing inherited blocking stdin does not necessarily interrupt a Go
read. Unix scripted stdio uses owned pollable duplicates and restores shared flags
after joining I/O. A retained `os.Process` alone does not guarantee identity:
Go can fall back to PID-only signaling on Unix. Script cancellation requires an
explicit Linux pidfd or Windows process handle and rejects unsupported identity
binding. Reap the target before closing input; Windows console stdin is rejected
before launch because Close does not interrupt its synchronous console read.
This avoids concurrent Delve Halt/Continue (which raced in the pinned backend).
Partial JSON writes must end
framing rather than append another event to an incomplete record. Evidence and
verification: [script shutdown/framing tests](../internal/debugger/script_test.go),
[stdio flags](../internal/debugger/script_file_unix_test.go), and
[native SIGINT and unread output](../tests/e2e/debug_script_test.go).

Verified: source modules such as `@std/yaml.ms` and `@std/toml.ms` enter inspection
and build source hashes but remain embedded virtual sources. Validate their bytes
from the pinned standard bundle, ignoring physical shadows. Map keys retain their
own load state; a truncated key prefix is not a complete identity. Evidence and
verification: [review regressions](../internal/debugger/review_regressions_test.go)
and [native standard-source sessions](../tests/e2e/debug_script_test.go).
Verified: the DAP Go-source launch modes, terminal Go-module path guessing, and an obsolete DWARF compatibility probe could still invoke external Go despite embedding Delve. The transport/client now exclude those routes; [vendor refresh](../scripts/maintenance/delve.go) reapplies the small compatibility-probe patch. Profile viewers are prebuilt into the SDK payload, not compiled on first use.

Verify: run the shutdown tests with `-race`, the native editor test, and the
six-target standalone distribution checks after changing Delve or its transport.

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

Verified: integration can expose an API in an additional reference without changing its declaration. Adding Map to the prelude and then adding Map methods required regenerating the prelude page and both downloads as well as the collections page. GitHub tested the combined merge tree while the local branch still passed freshness; [the failed freshness gate](https://github.com/manuscript-lang/manuscript/actions/runs/38431272729) identified this drift. Run `make docs` and freshness checks after latest-main integration, using the canonical registry rather than editing generated pages by hand.

Apply when: removing or renaming public language/API surface, or reporting a documentation update complete.
Evidence: the user's follow-up to [the concurrency change](https://github.com/manuscript-lang/manuscript/pull/24); [publication checks](../tests/docs/publication.test.cjs); [publishing workflow](../.github/workflows/cicd.yml).
Verify: regenerate both reference sources and the website with destination cleanup; compare shipped schema downloads against current generated sources, reject obsolete module routes, and search rendered pages and search data for retired terminology. Confirm publication separately from a successful source merge. Historical review text must not reintroduce syntax the user explicitly requested removing.

### Diagnostics are `<cause>; <fix>`, and tools key on the cause

Verified: agents act on a diagnostic only when it names the cause, the location, and a concrete fix (nearest name, import line, valid options). Messages therefore read `<cause>; <fix>`. `Diagnostic.Code` classifies only the text before the first `; `, so fix text cannot change a rule code. Partial parsing recovers from an unterminated delimiter by matching the message prefix, and the lexer reports it at end of file; moving that position or exact wording breaks editor recovery. A follow-on error that only restates `<invalid>` after an unknown name or operand mismatch is suppressed, but a genuine mismatch that mentions `<invalid>` (callback arity) must still surface.

Apply when: adding or rewording any lexer, parser, checker, project, compiler, CLI, or runtime message.
Evidence: [message-shape rule](../documentation/developer-tooling/source/diagnostics.md), [catalogue](../documentation/contributing/diagnostics-catalogue.md), [checker hints](../pkg/checker/hints.go), [hint tests](../pkg/checker/hints_test.go), and [recovery](../pkg/parser/partial.go).
Verify: run `go test ./pkg/checker ./pkg/parser ./pkg/tooling/lsp ./internal/cli`; extend the hint tests with the new message.
