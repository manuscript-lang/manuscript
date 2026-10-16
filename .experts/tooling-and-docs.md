# Tooling and documentation lessons

### Readable formatting needs paragraphs while retaining inline guards

Decision: the user's formatter request keeps inline `if` bodies and introduces
natural reading boundaries around declarations, guard sections, substantial
control flow. Later feedback in [issue #102](https://github.com/manuscript-lang/manuscript/issues/102)
requested authored spacing between match arms and compact short lists and
callback signatures. The latest user direction supersedes authored spacing:
discard authored blank lines and derive paragraphs from syntax. This also requires wrapping complex
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

Update: later feedback asks for compact output that reads well on a phone and a
desktop. Use syntax and printed width to keep single-step blocks with adjacent work and
pack simple list elements into width-limited rows. Discard authored blank lines,
including those between match arms; derive paragraphs from structural rules.
Wrap only when a group exceeds 88 columns or holds a comment or
multi-statement suite; clause counts, argument counts, lambdas, and authored line
breaks no longer force expansion. Reintroducing such rules spreads code again.

Verified: formatter policy changes also require refreshing the pinned standard
sources, because exported editor files must pass `ms fmt --check`.
[TestPinnedSources](../pkg/stdlib/sources_test.go) checks canonical source text
in the fast unit gate; the exported-source integration test verifies the CLI and
editor surfaces. Keep generic file headers out of declaration documentation when
blank lines are discarded.

### Inspect active List backing in the debugger

Verified: typed List storage adds inactive nil slice fields to the native header.
Rendering `Items` alone exposed bookkeeping or an empty fallback instead of source
elements. Read the kind tag for expansion and indexed watches; Delve displays a
uint8 as `1 = 0x1`, so parse its decimal prefix. Do not infer backing from a source
primitive type because legacy/large literals can still be boxed. Evidence:
[primitive and native DAP regressions](../extensions/vscode/tests/debug-adapter.test.js)
and [storage-aware renderer](../extensions/vscode/debug-adapter.js).
Verify all four primitive backings, legacy/empty Lists, generic types and watch
indexing; source values must not expose private header fields or inactive lengths.

### Editor recovery must preserve delimiter continuations

Verified: strict parsing accepts multiline parameters, but declaration recovery previously split their column-zero closing delimiters into separate chunks whenever any declaration was malformed. This discarded valid functions and their parameter scopes in the LSP. Recovery now consults the lexer for continuation boundaries while fresh declarations still synchronize after an unmatched opener. Completion snapshots also need a match arm, rather than an ordinary statement, to repair an unfinished `match` suite.

Apply when: changing partial parsing, declaration synchronization, or completion snapshot repair.
Evidence: [layout rules](../documentation/core-language/basics/grammar.md#layout-tokens); [recovery regressions](../pkg/parser/partial_test.go); [parameter navigation regression](../pkg/tooling/lsp/analysis_test.go); [completion regressions](../pkg/tooling/lsp/completion_test.go).
Verify: multiline function parameters retain their original LF/CRLF positions, navigation, and completion when a different declaration is incomplete; an unfinished match does not erase completion in the enclosing function.

### Standard declarations are source that tools must navigate

Decision: the user asked to keep standard type definitions in Manuscript so editor tooling can use them. Verified architecture: `pkg/stdlib/*.ms` supplies public schemas and signatures; `bindings.json` maps identities to native dispatch. Generated documentation and navigation consume this source-backed contract.

Verified: bundled modules containing bodies use ordinary Manuscript parsing, checking, and lowering. Recheck reachable source implementations in each program rather than mutating shared registry symbols. Publish only module-owned exports: a checked module's name table also contains imported symbols and prelude types, which must not become new exports. Native declarations retain empty bodies and ABI bindings; all standard modules use ordinary parsing. Evidence: [standard source loader](../pkg/checker/standard.go), [reachability and visibility regressions](../pkg/compiler/source_stdlib_test.go), and [source navigation](../pkg/tooling/lsp/navigation_test.go).

Verified: navigation must continue after the first jump into a standard declaration. Register the virtual document scheme with the language client and retain the standard loader's resolved type references for tooling; reparsing library signatures as executable workspace modules loses their checked context. Keep virtual documents immutable and outside workspace source overlays.

Verified: standard source syntax must also pass ordinary `parser.Parse` and formatting. A permissive library-only parser concealed missing bodies, mixed receiver signatures, and field-default errors. The user requires ordinary empty functions with colon headers, including receiver functions, and empty opaque schemas with colons. Do not replace these with a `native` modifier. Binding authorization belongs to checking. Disk editor documents reuse pinned bindings only for exact source matches, while syntax validity is independently tested. Both repo-check modes validate working-tree stdlib sources through the strict frontend and return a positioned error before checker initialization, so `make check`, `make repo-check`, and CI verification reject invalid syntax directly. Evidence: [all-source parsing and formatting](../pkg/stdlib/sources_test.go), [empty-function grammar boundaries](../pkg/parser/empty_declarations_test.go), [disk document checks](../pkg/tooling/lsp/standard_test.go), and [syntax gate regressions](../scripts/repo-check/main_test.go).

Apply when: adding standard APIs, changing their signatures, or extending hover/navigation/documentation.
Evidence: [declaration ownership](../pkg/stdlib/intrinsics.ms); [embedded sources](../pkg/stdlib/sources.go); [documentation generator](../scripts/docgen/main.go).
Evidence for continued navigation: [standard loader](../pkg/checker/standard.go), [virtual document analysis](../pkg/tooling/lsp/analysis.go), [navigation regression tests](../pkg/tooling/lsp/features_test.go), [read-only session test](../pkg/tooling/lsp/server_test.go), and [client restart test](../extensions/vscode/tests/extension.test.js).
Verify: native calling signatures agree with the declarations, editor definitions reach the declaration and can follow imports and signature types from there, and source documentation and the generated book pass their checks. Update the source or generator when output changes. Regenerate from combined source after integration: adding List/Map to the prelude makes their receiver additions appear in the prelude reference as well as the collections reference. Conflict-free merges can still leave generated prelude/download artifacts stale; post-merge docs-check caught this for #262/#269, and combined generation restores those methods. Member-description extraction changes also require combined regeneration, even when merged signature strings remain current.

Decision: the string utility module is `@std/string.ms`, matching the intrinsic `String` type. The user requested this spelling when expanding built-in parity. Receiver operations need no module import; standalone string functions use this canonical module. Evidence: [declarations](../pkg/stdlib/string.ms), [native bindings](../pkg/stdlib/bindings.json), and [data package guide](../pkg/stdlib/collections.ms). When renaming a module, verify imports, native dispatch identities, virtual editor documents, and generated reference paths together.

### Keep CLI and HTTP documentation with their packages

Decision: the user explicitly removed the “Application hosts” section. CLI entry/accessor/shutdown contracts belong in the CLI package guide, and HTTP request/shutdown contracts belong in the HTTP package guide. Do not recreate a separate host category in the standard-library navigation.

Apply when: organizing the standard-library guide or adding application-entry documentation.
Evidence: [standard-library navigation](../pkg/stdlib/intrinsics.ms), [CLI guide](../pkg/stdlib/cli.ms), and [HTTP guide](../pkg/stdlib/http.ms).
Verify: build the book with destination cleanup and confirm there is no standard-library/hosts route or sidebar section; existing entry and request links resolve to package pages.

### Teach a runnable path before formal reference

Decision: public documentation should focus on Manuscript and what readers can build. Remove comparisons with other languages, coverage maps, implementation inventories, and review bookkeeping. Keep one getting-started guide; modules, references, and cleanup belong in the language reference, application builds in developer tools, and compiler internals in contributor documentation. Use clear topic names and keep the sidebar, overview, and reading order consistent. Teach basics, functions, types, control flow, errors, modules, and resource management before library services and concurrent work. Library topics should be directly reachable; group scheduling, sharing, synchronization, and queues with concurrent work. State availability and limits beside the affected feature. Use practical, example-first progression through variables, collections, functions, types, errors, and modules; keep indexes short and link to exact rules. Clearly separate intentional rejection examples from the usual runnable path. A basic destructuring example should not require task-group work and error propagation.

Apply when: adding tutorials, revising design chapters, or explaining new syntax.
Evidence: [learn index](../documentation/learn/_index.md).
Verify: run the displayed source and commands with the stated prerequisites; check that the reading path introduces dependencies before using them. Sidebar and previous/next links use the same [navigation order](../website/data/navigation.toml); the [publication checks](../tests/docs/publication.test.cjs) compare their rendered order. Build the book with its current strict checks and link to canonical rules instead of repeating them.

Verified: a `manuscript-example` annotation alone does not put a chapter into the executable example suite. The harness discovers introductory tutorials and explicitly listed guides; the logging guide needed an inventory entry before its annotated stdout example was checked or run. See [the example inventory](../tests/examples/examples_test.go) and [the logging example](../pkg/stdlib/log.ms). When adding complete examples outside the introductory chapters, confirm that their file appears in the harness and run its named subtest with `MANUSCRIPT_EXAMPLES_NATIVE=1`.

Task recipes must also preserve I/O failure: matching a failed stdout write and returning success hides an undelivered result. [Common tasks](../documentation/learn/common-tasks.md) forwards write/flush errors to a nonzero entry status. The same [example harness](../tests/examples/examples_test.go) supplies isolated files, stdin, and loopback HTTP plus additional expected-failure cases; type checking alone cannot establish the displayed output, EOF handling, or failure status. See [annotation fields and native execution](../documentation/contributing/development.md#conformance-and-coverage).

### User tooling must work in the shipped binary

Decision: documentation generation was requested as an `ms` subcommand for users, rather than only a repository generator. Native builds were subsequently requested to work from a single binary without separately installing Go, with CGO excluded. The later requirement makes the bundled toolchain mandatory: no external override, PATH fallback, or ambient Go configuration may select another tool. OS-specific prerequisites such as Apple debugserver remain permitted. This establishes a delivery boundary for user-facing tooling: test the command from the user's installation context.

Apply when: adding CLI tooling or making claims about installation requirements.
Evidence: [native build contract](../documentation/developer-tooling/builds/reproducibility.md); [payload construction](../scripts/mktoolchain/main.go); [standalone distribution checks](../scripts/distcheck/main.go).
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
Verified: the DAP Go-source launch modes, terminal Go-module path guessing, and an obsolete DWARF compatibility probe could still invoke external Go despite embedding Delve. The transport/client now exclude those routes; [vendor refresh](../scripts/maintenance/delve.go) reapplies the small compatibility-probe patch. Profile viewers are prebuilt into the SDK payload, not compiled on first use.

Verified: terminal Close only restores modes; it does not interrupt a blocked
prompt. Embedded terminal sessions need owned interruptible stdio, a joined
SIGINT guard, and canceled prompt deliveries before restoring borrowed handles.
On Unix, set nonblocking mode before constructing the duplicate so Delve's
paging writer calling `Fd` cannot disable cancellation; restore shared flags
after target shutdown. Windows console input bypasses Go's file reader, so
cancel the stable worker thread's synchronous I/O until it joins and restore
console modes through the original handles. [Vendor refresh](../scripts/maintenance/delve_terminal.go)
preserves the small terminal/liner lifecycle patches. Evidence:
[owned I/O](../internal/debugger/io.go), [native lifecycle regressions](../internal/debugger/native_lifecycle_test.go),
and [Windows console regression](../internal/debugger/process_windows_test.go).
Verify console behavior on a native Windows host; pipe tests and cross-compilation
do not validate `ReadConsoleInputW` cancellation or console mode restoration.

Verified: a fatal command-reader error must be latched before reporting it;
stop the target before a bounded, joined diagnostic attempt. A final CLI stderr
write can block again when stderr shares the unread event-output pipe, so it
uses the same owned reporting path. Identify the null device by descriptor
identity, since inherited stdio retains names such as `/dev/stdin` even when
redirected to `/dev/null`. Evidence: [full-output and redirected-stream cases](../internal/debugger/native_lifecycle_test.go),
[shared-output CLI regression](../tests/e2e/debug_script_cancel_unix_test.go),
and [borrowed descriptor/deadline regressions](../internal/debugger/io_unix_test.go).
These are debugger-owned CLI transports; they do not change the runtime/stdlib
stdio cancellation contract.

Verified: Delve consumes `OutputRedirect.File` and closes it after Windows
launch. Scripted JSON redirects must pass distinct owned stderr duplicates,
with fallback cleanup for failed launches; passing borrowed `os.Stderr` closes
the caller's diagnostics. Evidence: [Delve redirect ownership](../vendor/github.com/go-delve/delve/pkg/proc/native/proc.go),
[Windows launch](../vendor/github.com/go-delve/delve/pkg/proc/native/proc_windows.go),
and [borrowed stderr regression](../internal/debugger/io_windows_test.go).
For full-pipe Windows tests, complete writes up to the queried pipe capacity;
a canceled oversized write does not establish retained buffer contents. Keep
test failure diagnostics on a separate file when stdio is unread or null.

Open: disconnecting the client joins client calls but does not stop an active
backend operation. Public service Stop still owns target cleanup. Delve resets
manual-stop requests before Continue, and gdbserial ignores manual stops while
its connection is outside Continue; prompt/stream cancellation tests do not
establish cancellation across every native step. Evidence:
[Continue](../vendor/github.com/go-delve/delve/pkg/proc/target_exec.go) and
[gdbserial stop](../vendor/github.com/go-delve/delve/pkg/proc/gdbserial/gdbserver.go).
Verify native cancellation during dispatch and single-step before expanding
the shutdown guarantee beyond the tested lifecycle paths.

Verify: run the shutdown tests with `-race`, the native editor test, and the
six-target standalone distribution checks after changing Delve or its transport.

### Polish the documentation design without expanding its prose

Decision: the user selected Tailwind CSS and Vercel as documentation design references and asked not to add filler. The later direction makes the landing page a marketing page whose goal is getting people to try Manuscript: lead with a concrete value proposition, a runnable example, and a clear first-run action. Keep learning pages focused on teaching and organize lessons, task guides, and reference by reader intent. This supersedes the earlier restriction on promotional homepage copy; it does not authorize unsupported claims or padded reference prose.

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

Verified: integration can expose an API in an additional reference without changing its declaration. Adding Map to the prelude and then adding Map methods required regenerating the prelude page and both downloads as well as the collections page. GitHub tested the combined merge tree while the local branch still passed freshness; [the failed freshness gate](https://github.com/manuscript-lang/manuscript/actions/runs/38431272729) identified this drift. Run `make docs` and `make book-check` after latest-main integration, using the canonical registry rather than editing generated pages by hand.

Apply when: removing or renaming public language/API surface, or reporting a documentation update complete.
Evidence: the user's follow-up to [the concurrency change](https://github.com/manuscript-lang/manuscript/pull/24); [publication checks](../tests/docs/publication.test.cjs); [publishing workflow](../.github/workflows/cicd.yml).
Verify: regenerate both reference sources and the website with destination cleanup; compare shipped schema downloads against current generated sources, reject obsolete module routes, and search rendered pages and search data for retired terminology. Confirm publication separately from a successful source merge. Historical review text must not reintroduce syntax the user explicitly requested removing.

### Diagnostics are `<cause>; <fix>`, and tools key on the cause

Verified: agents act on a diagnostic only when it names the cause, the location, and a concrete fix (nearest name, import line, valid options). Messages therefore read `<cause>; <fix>`. `Diagnostic.Code` classifies only the text before the first `; `, so fix text cannot change a rule code. Partial parsing recovers from an unterminated delimiter by matching the message prefix, and the lexer reports it at end of file; moving that position or exact wording breaks editor recovery. A follow-on error that only restates `<invalid>` after an unknown name or operand mismatch is suppressed, but a genuine mismatch that mentions `<invalid>` (callback arity) must still surface.

Apply when: adding or rewording any lexer, parser, checker, project, compiler, CLI, or runtime message.
Evidence: [message-shape rule](../documentation/developer-tooling/source/diagnostics.md), [checker hints](../pkg/checker/hints.go), [hint tests](../pkg/checker/hints_test.go), and [recovery](../pkg/parser/partial.go).
Verify: run `go test ./pkg/checker ./pkg/parser ./pkg/tooling/lsp ./internal/cli`; extend the hint tests with the new message.

### Debug by Manuscript position, not Go symbol
Verified: in a Debug build `main.main` is generated glue (`initialize()` then the runtime entry), and each Manuscript function is a closure under `initialize` (`main.initialize.func1.1`), so Go symbols never name user code. Line directives map `file.ms:line` stably. Generated position bookkeeping between statements inherits phantom line numbers (a step can stop on a blank line after a statement), and `ms inspect` function entities carry only a header line, so function extent comes from the next declaration and a function breakpoint uses the first statement after the header. Scripted `ms debug` resolves names through inspection for this reason.

Apply when: changing source maps, line directives, inspection spans, or the scripted debugger.
Evidence: [session driver](../internal/debugger/session.go), [name mapping](../internal/cli/debug_names.go), [end-to-end debug tests](../tests/e2e/debug_script_test.go), [scripted debugging](../documentation/developer-tooling/debugging/debugger-integration.md#scripted-debugging-for-agents).
Verify: `go test ./tests/e2e -run TestDebug`; a `next` over a statement must land on the next statement line, not a blank line.

### Standard-library prose has the same owner as declarations

Decision: the user requires `.ms` standard-library sources to own all library
documentation. Guide and special-call-rule comment blocks ship with the pinned
sources; generated Markdown is disposable and lives under `.artifacts/docs/`.
Keep existing routes when moving prose. Concurrency API contracts belong with
`tasks.ms`, `sync.ms`, `queues.ms`, and `process.ms`.

Apply when: changing library docs or the book pipeline.
Evidence: [guide extraction](../pkg/tooling/docgen/guides.go),
[generation](../scripts/docgen/main.go), and
[source example discovery](../tests/examples/examples_test.go).
Verify: source checks and tutorial discovery work without generated Markdown;
`make book-check` generates the mounted pages and validates routes and downloads.

### Agent help is CLI commands, not a protocol server

Decision: the user evaluated an MCP server (PR #528), judged the CLI the better surface for coding agents, and had it removed. Agents with a shell already get compact output from `check`, `lint`, `fmt`, and `test`; the gaps became `ms search_symbol` and `ms guide`. Navigation is by name, not `file:line:col`, because agents track names better than positions; `ms search_symbol` wraps the language server's workspace symbols, definition and references, and the next language-server feature to expose is a checked rename. A bare `ms search` read as generic and `ms guide stdlib <module>` printed 42 KB for the prelude, so library lookup folded into `ms search_symbol` (names and words search project and library; a lone module or `<module>[.Decl[.member]]` path shows a page) and every page has a byte budget that `TestStdPagesStayBounded` checks over all declarations. Keep the command set small and useful. Search is fuzzy, the guide stays short because agents reread it, and pages are built from `checker.StandardLibrary()`, never from `ms doc` or `ms stdlib` (both removed). A new `--json` command must join `jsonCommands`.

Apply when: adding agent-facing commands, changing search ranking, or touching the cheat sheet or standard-library index.
Evidence: [search](../pkg/tooling/guide/search.go), [guide](../pkg/tooling/guide/guide.go), [cheat sheet](../pkg/tooling/guide/cheatsheet.md), [commands](../internal/cli/agent.go), and [agent commands](../documentation/developer-tooling/implementation.md#commands-for-agents).
Verify: `go test ./pkg/tooling/guide ./internal/cli`; search tests pin typo, synonym, partial, and dedup behavior; the cheat sheet's program must check and stay under 2,500 bytes.
