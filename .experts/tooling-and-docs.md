# Tooling and documentation lessons

The Go debugger (embedded Delve, DAP, scripted `ms debug`) and Go toolchain bundling are gone. `ms emit` now prints MIR, not standalone Go source. The native profiler `ms profile` replaced the debugger; lessons about those Go-era tools were removed with them.

### Project review must keep library internals behind their boundary

Verified: inspection deliberately includes bundled standard source modules. Feeding every inspection entity into a project review makes even the hello project show hundreds of library entities before its own entry point. Review facts and diagrams exclude standard declarations while retaining calls into them as external boundaries and imports as dependencies. An unscoped call view also needs roots for disconnected recursive groups: selecting only declarations with no callers silently loses them.

Apply when: changing inspection consumers, review facts, or diagram roots.
Evidence: [fact collection](../crates/ms-tooling/src/collect.rs), [CLI regressions](../crates/ms-cli/tests/review_diagram.rs), [view regressions](../crates/ms-tooling/tests/review.rs), [output contract](../documentation/developer-tooling/implementation.md#review-report).
Verify: a program importing process arguments has one project entry point in its review and keeps the standard call as a diagram leaf; recursive groups remain visible without `--entity`; an explanation's stable ID selects the same finding in a diff-marked JSON diagram.

### Readable formatting needs paragraphs while retaining inline guards

Decision: the user's formatter request keeps inline `if` bodies and introduces natural reading boundaries around declarations, guard sections, substantial control flow. Later feedback in [issue #102](https://github.com/manuscript-lang/manuscript/issues/102) requested authored spacing between match arms and compact short lists and callback signatures. The latest user direction supersedes authored spacing: discard authored blank lines and derive paragraphs from syntax. This also requires wrapping complex expressions; paragraph breaks alone leave dense calls and conditions unreadable. Do not expand inline bodies to create readability or guess business stages from adjacent call names.

Update: later feedback asks for compact output that reads well on a phone and a desktop. Use syntax and printed width to keep single-step blocks with adjacent work and pack simple list elements into width-limited rows. Wrap only when a group exceeds 88 columns or holds a comment or multi-statement suite; clause counts, argument counts, lambdas, and authored line breaks no longer force expansion. Reintroducing such rules spreads code again. Existing call, collection, and parameter delimiters already allow item continuations; adding parentheses before measuring the item's final indentation creates redundant groups. Break long item operators within those delimiters and verify precedence and idempotence.

Apply when: changing source formatting or adding layout heuristics.
Evidence: [formatting policy](../documentation/developer-tooling/implementation.md#linting-and-formatting), [formatter](../crates/ms-syntax/src/format.rs), [formatter CLI tests](../crates/ms-cli/tests/fmt.rs), [format corpus](../crates/ms-syntax/tests/data/format).
Verify: setup stays with its immediate uses and simple return; guards stay attached to setup and following work starts a paragraph; section comments stay attached to their code and substantial callbacks get their own paragraphs; branch families remain together; LF/CRLF output preserves literal spellings and is identical after a second format. Added grouping must preserve the entire parsed syntax tree, especially inline callback return boundaries and mixed-precedence conditions. Moving a callback argument must move its suite indentation too. When a parameter default contains a suite, header alignment must skip layout tokens inside its enclosing delimiters; verify the enclosing function body stays aligned after a second format with [the default-callback fixture](../crates/ms-syntax/tests/data/format/043.in.src). A later call in a chain must budget its own arguments; a callback body must not consume the parameter signature's width budget.

Verified: formatter policy changes also require reformatting the repository's `.ms` files, including `stdlib/`, because `make repo-check` checks `.ms` formatting and stdlib syntax. Keep generic file headers out of declaration documentation when blank lines are discarded.

Decision: remove redundant argument labels from ordinary test assertions. The latest direction is for formatted code to read like prose: keep each setup, action, and check together, then start a paragraph at the next setup or a section comment. Do not isolate a short binding from its immediate use or simple return. Give substantial callbacks their own paragraphs, and retain attached guards. Verify these reading boundaries with [the prose fixture](../crates/ms-syntax/tests/data/format/042.in.src).

Correction: a single explicit-return callback should not keep an unnecessary indented body when its call fits, e.g. `queue.enqueue(lambda: return 7)`. Preserve comments and nested suites; never compact a bare call body into an implicit return. Verify LF/CRLF and idempotence with [the callback fixture](../crates/ms-syntax/tests/data/format/041.in.src).

### Editor recovery must preserve delimiter continuations

Verified: strict parsing accepts multiline parameters, but declaration recovery that splits their column-zero closing delimiters into separate chunks whenever any declaration is malformed discards valid functions and their parameter scopes in the language server. Recovery must consult the lexer for continuation boundaries while fresh declarations still synchronize after an unmatched opener. Completion snapshots also need a match arm, rather than an ordinary statement, to repair an unfinished `match` suite.

Apply when: changing partial parsing, declaration synchronization, or completion snapshot repair.
Evidence: [layout rules](../documentation/core-language/basics/grammar.md#layout-tokens); [partial parsing](../crates/ms-syntax/src/partial.rs); [completion](../crates/ms-lsp/src/completion.rs); [partial parse corpus](../crates/ms-syntax/tests/data/partial).
Verify: multiline function parameters retain their original LF/CRLF positions, navigation, and completion when a different declaration is incomplete; an unfinished match does not erase completion in the enclosing function.

### Shared editor analysis must preserve selected roots and overlays

Verified: resolve the nearest manifest before sharing analysis. A standalone file symlink can select a different source root and confinement error from its destination; a symlinked manifest retains its containing directory. Distinct URIs can decode to one filename with different requested text, so those overlays cannot share a checked result. Keep default and selected-module recovery separate, private completion repair uncached, and strict workspace graphs transient. Apply queued incremental ranges in order and publish the newest errors before request, close, and EOF barriers.

Apply when: changing language-server analysis caching, workspaces, or scheduling.
Evidence: [analysis](../crates/ms-lsp/src/analysis.rs), [workspace](../crates/ms-lsp/src/workspace.rs), [overlays](../crates/ms-driver/src/project/overlay.rs), [snapshot tests](../crates/ms-lsp/tests/snapshots.rs).
Verify: compare cached results with uncached analysis in both query orders.

### Standard declarations are source that tools must navigate

Decision: the user asked to keep standard type definitions in Manuscript so editor tooling can use them. `stdlib/*.ms` supplies public schemas and signatures; `bindings.json` maps identities to native dispatch. Generated documentation and navigation consume this source-backed contract.

Verified: bundled modules containing bodies use ordinary Manuscript parsing and checking. Publish only module-owned exports: a checked module's name table also contains imported symbols and prelude types, which must not become new exports. Native declarations retain empty bodies and ABI bindings; all standard modules use ordinary parsing. The user requires ordinary empty functions with colon headers, including receiver functions, and empty opaque schemas with colons. Do not replace these with a `native` modifier, and do not hide invalid syntax in a permissive library-only parser (that once concealed missing bodies, mixed receiver signatures, and field-default errors). `make repo-check` validates working-tree stdlib sources and returns a positioned error before checker initialization.

Verified: navigation must continue after the first jump into a standard declaration. Register the virtual document scheme with the language client and keep the resolved type references for tooling; reparsing library signatures as executable workspace modules loses their checked context. Keep virtual documents immutable and outside workspace source overlays.

Apply when: adding standard APIs, changing their signatures, or extending hover/navigation/documentation.
Evidence: [declaration ownership](../stdlib/intrinsics.ms); [standard checking](../crates/ms-check/src/stdlib.rs); [documentation generator](../crates/ms-tooling/src/guide/docgen.rs); [client](../extensions/vscode/extension.js); [client tests](../extensions/vscode/tests/extension.test.js).
Verify: native calling signatures agree with the declarations, editor definitions reach the declaration and can follow imports and signature types from there, and source documentation and the generated book pass their checks (`make docs-check`). Regenerate from combined source after integration: adding List/Map to the prelude makes their receiver additions appear in the prelude reference as well as the collections reference, and a conflict-free merge can still leave generated artifacts stale. Member-description extraction changes also require combined regeneration, even when merged signature strings remain current.

Decision: the string utility module is `@std/string.ms`, matching the intrinsic `String` type. The user requested this spelling when expanding built-in parity. Receiver operations need no module import; standalone string functions use this canonical module. Evidence: [declarations](../stdlib/string.ms), [native bindings](../stdlib/bindings.json), and [data package guide](../stdlib/collections.ms). When renaming a module, verify imports, native dispatch identities, virtual editor documents, and generated reference paths together.

### Keep CLI and HTTP documentation with their packages

Decision: the user explicitly removed the "Application hosts" section. CLI entry/accessor/shutdown contracts belong in the CLI package guide, and HTTP request/shutdown contracts belong in the HTTP package guide. Do not recreate a separate host category in the standard-library navigation.

Apply when: organizing the standard-library guide or adding application-entry documentation.
Evidence: [standard-library navigation](../stdlib/intrinsics.ms), [CLI guide](../stdlib/process.ms), [HTTP guide](../stdlib/http.ms).
Verify: build the book with destination cleanup and confirm there is no standard-library/hosts route or sidebar section; existing entry and request links resolve to package pages.

### Teach a runnable path before formal reference

Decision: public documentation should focus on Manuscript and what readers can build. Remove comparisons with other languages, coverage maps, implementation inventories, and review bookkeeping. Keep one getting-started guide; modules, references, and cleanup belong in the language reference, application builds in developer tools, and compiler internals in contributor documentation. Use clear topic names and keep the sidebar, overview, and reading order consistent. Teach basics, functions, types, control flow, errors, modules, and resource management before library services. Library topics should be directly reachable. State availability and limits beside the affected feature. Use practical, example-first progression through variables, collections, functions, types, errors, and modules; keep indexes short and link to exact rules. Clearly separate intentional rejection examples from the usual runnable path.

Apply when: adding tutorials, revising design chapters, or explaining new syntax.
Evidence: [learn index](../documentation/learn/_index.md).
Verify: run the displayed source and commands with the stated prerequisites; check that the reading path introduces dependencies before using them. Sidebar and previous/next links use the same [navigation order](../website/data/navigation.toml); the [publication checks](../tests/docs/publication.test.cjs) compare their rendered order. Build the book with its current strict checks and link to canonical rules instead of repeating them.

Verified: task recipes must preserve I/O failure: matching a failed stdout write and returning success hides an undelivered result. [Common tasks](../documentation/learn/common-tasks.md) forwards write/flush errors to a nonzero entry status. Type checking alone cannot establish the displayed output, EOF handling, or failure status; a complete example needs an executed check, and the docs and examples categories of the [conformance corpus](../tests/conformance/README.md) are where fences are run.

### User tooling must work in the shipped binary

Decision: documentation generation was requested as an `ms` subcommand for users, rather than only a repository generator. Native builds were requested to work from the installed `ms` alone. Today linking uses the system `cc`/`ld`, and a bundled linker is a tracked follow-up ([design contract](../crates/DESIGN.md)); do not claim a stronger installation guarantee than the packaged check demonstrates. OS-specific prerequisites remain permitted. This establishes a delivery boundary for user-facing tooling: test the command from the user's installation context, not only from the checkout.

Verified: `vscode-languageclient` 10 requires a log output channel, including `onDidChangeLogLevel` and severity methods. A plain output channel fails during editor activation even when a direct compiler LSP handshake succeeds. Create the shared channel with `{ log: True }`; activation and restart tests must exercise the logging API rather than making client startup a no-op.

Apply when: adding CLI tooling, upgrading the editor client, or making claims about installation requirements.
Evidence: [client setup](../extensions/vscode/extension.js), [dependency pin](../extensions/vscode/package-lock.json), [activation/restart regression](../extensions/vscode/tests/extension.test.js), [packaging script](../scripts/package-rust.sh), [packaged binary check](../scripts/dist-check.sh), [native build contract](../documentation/developer-tooling/how-it-works.md).
Verify: `make dist-check` extracts the archive for this host and runs the packaged binary on the hello example; additionally exercise a copied binary outside the checkout with empty caches.

### Profile native programs by Manuscript position

Decision: `ms profile` replaces the debugger (the debugger and DAP are dropped). It captures sampling profiles of a native program (folded stacks, pprof-compatible output, and a `perf` map file) using frame pointers plus a PC-to-source table, and `perf record` works on any `ms build` output because the compiler keeps frame pointers and emits a perf map and DWARF line tables ([design contract](../crates/DESIGN.md)). Report positions as `file.ms:line`, never as symbols or addresses of generated code.

Apply when: changing source maps, line tables, the perf map, or profile output formats.
Evidence: [runtime profiling](../crates/ms-rt/src/profile.rs), [profile CLI tests](../crates/ms-cli/tests/profile.rs), [debug artifact tests](../crates/ms-build/tests/debug_artifacts.rs).
Verify: `cargo nextest run -p ms-cli -p ms-build`; a profile of a small program attributes samples to Manuscript lines. Treat the pages under `documentation/developer-tooling/debugging/` as possibly stale until checked against `ms profile`.

### Polish the documentation design without expanding its prose

Decision: the user selected Tailwind CSS and Vercel as documentation design references and asked not to add filler. The later direction makes the landing page a marketing page whose goal is getting people to try Manuscript: lead with "The language for the agentic era." as the hero headline, a runnable example, and a clear first-run action. The follow-up correction asks for a hero instead of a wall of text: use one compact focal area with a headline, short promise, primary action, and code preview; avoid stacking repeated benefit paragraphs and card sections on the homepage. Explain why Manuscript through the vision and README: agents write and humans understand, with compact evidence from API-first design, minimal syntax, and compiler-backed tools. Keep learning pages focused on teaching and organize lessons, task guides, and reference by reader intent. This supersedes the earlier restriction on promotional homepage copy; it does not authorize unsupported claims or padded reference prose.

Decision: after the broader reader-journey redesign, the user asked, "can we do landing page as hero instead of wall text?" Use a focused hero with a large headline, short description, prominent trial action, secondary tour link, and compact code/output preview. Remove repeated benefit paragraphs and stacked cards when applying this direction. Evidence: the request in **Update docs for current language**, following [the reader-journey change](https://github.com/manuscript-lang/manuscript/pull/570), and [the resulting hero revision](https://github.com/manuscript-lang/manuscript/pull/573). Later direction: the landing page must also lay out the benefits clearly. Keep the hero, then one compact "Why Manuscript" grid of short, shipped-feature benefits below the example (no stacked paragraphs); this refines, not reverses, the hero decision. Keep claims tied to shipped features and keep VISION.md's "Where things stand" in sync.
Verify: inspect desktop and narrow mobile renders in both themes; the first action and example remain readable with brief supporting copy. This records the requested direction; verify its implementation in the checkout being edited.

Decision: keep the established headline “The language for the agentic era.” and lead with agents writing code that people can understand. Use concrete reasons—familiar syntax, native programs, actionable feedback, visible ownership and scoped concurrency—in short sections. The requested tone is direct and non-cheeky; keep “ideal language” claims out of the opening. Explain long-term ambition in the [vision](../VISION.md), with current benefits in the [README](../README.md) and [rationale](../documentation/learn/why-manuscript.md).

Decision (2026-10-25 documentation refresh): public positioning is alpha. This describes maturity, not proof that a versioned archive has been published. The user asked not to discuss individual bugs in this refresh; keep the README, landing page and onboarding focused on current capabilities and the alpha status, without turning them into issue inventories. This does not establish stability or remove the need to verify examples. Evidence: the user’s latest instruction and the [README status](../README.md), [quickstart](../documentation/learn/getting-started.md), and [landing copy](../website/layouts/_shortcodes/docs-home.html).

Decision: the user requested an orange brand tint and a professional logo to replace the italic badge. Use the custom orange `ms` lettermark with two separate lowercase characters and a visible gap (no ligature) consistently in the header and favicon, with orange accents and readable foreground/background pairs in both themes. Check the mark at desktop and mobile sizes when changing [branding](../website/layouts/_partials/docs/brand.html) or [favicon generation](../website/layouts/_partials/docs/html-head-favicon.html).

Apply when: redesigning the documentation shell or overview, or extending its visual system.
Evidence: the user's documentation redesign correction; [Tailwind docs](https://tailwindcss.com/docs/installation/using-vite); [Vercel docs](https://vercel.com/docs); [site-owned visual system](../website/assets/_custom.scss); [overview presentation](../website/layouts/_shortcodes/docs-home.html).

Decision: the user requested reuse of VS Code highlighting code where possible. The docs use the extension's [TextMate grammar](../extensions/vscode/syntaxes/manuscript.tmLanguage.json) as their single source of lexical rules, through a small [browser adapter](../website/assets/manuscript-highlight.js). Keep language patterns in the shared grammar instead of adding a separate keyword list for the website.

Decision: present API classifications as human-readable badges beside symbol headings, instead of exposing compiler labels such as `Kind: fn.` as prose. The [generator](../crates/ms-tooling/src/guide/docgen.rs) keeps portable Markdown readable and raw JSON kinds stable; the [heading renderer](../website/layouts/_markup/render-heading.html) adds badges without changing symbol anchors or table-of-contents labels. Check rendered pages when changing this metadata.

Decision: show API excerpts in regular Manuscript declaration syntax, rather than checker dumps such as `DnsRecord: DnsRecord`, `field kind: String`, or `operation receive: Callable[[...], Unit]->...`. Generate fields, cases, methods, and generic bounds from the source declarations, omitting implementation bodies. Compiler-bound calls without an ordinary declaration link to their special call rules rather than displaying `<unknown>` as a type. Verify CLI output and published pages together; keep the machine-readable JSON contract stable.

Verified: styling a code container did not highlight Manuscript examples fenced as `text`. Explicit `manuscript` fences use the shared grammar, with [tokenization checks](../tests/docs/highlighting.test.cjs). The documentation generator emits the same language label so regenerated API pages retain highlighting.

Verified: a shared grammar update can outgrow the browser adapter. The `f"` opener was matched but not scanned as a complete string, so its closing quote swallowed the remaining example; numeric bases and separators and obsolete contextual words also drifted. Interpret nested includes, captures, escapes and interpolation from the shared rules, keeping braces literal in ordinary strings. The [tokenization checks](../tests/docs/highlighting.test.cjs) inventory compiler keywords and symbols and cover the [parser fixture](../tests/docs/syntax.ms); the [publication checks](../tests/docs/publication.test.cjs) execute the generated browser bundle against that fixture and the landing example. Verify grammar changes with the TextMate engine too: a regex accepted by JavaScript can be rejected by Oniguruma.

Verify: compare authored Markdown with the base branch, keep semantic changes out of visual work, check desktop and mobile reading pages, and run the strict Hugo build with a repository URL prefix (`make book-check`). Verify actual token colors in light and dark mode, unchanged copied text, and plain terminal output. Exercise the primary CTA as a visited link: the theme's `.markdown a[href]:visited` rule can override a less-specific button selector and hide its label. Give the component explicit visited colors and check the rendered state. Build `.artifacts/book/` from the current sources; never resolve generated-page conflicts by retaining stale output.

### Source freshness does not establish published freshness

Verified: after the concurrency simplification, source declarations and generated Markdown were current while the checked-in website still exposed retired bounds and a removed module route. The user found this in the API reference. A source-generation check alone cannot verify the HTML, downloadable schemas, or search index that readers receive.

Verified: integration can expose an API in an additional reference without changing its declaration. Adding Map to the prelude and then adding Map methods required regenerating the prelude page and both downloads as well as the collections page. GitHub tested the combined merge tree while the local branch still passed freshness; [the failed freshness gate](https://github.com/manuscript-lang/manuscript/actions/runs/38431272729) identified this drift. Run `make docs` and `make book-check` after latest-main integration, using the canonical registry rather than editing generated pages by hand.

Apply when: removing or renaming public language/API surface, or reporting a documentation update complete.
Evidence: the user's follow-up to [the concurrency change](https://github.com/manuscript-lang/manuscript/pull/24); [publication checks](../tests/docs/publication.test.cjs); [publishing workflow](../.github/workflows/cicd.yml).
Verify: regenerate both reference sources and the website with destination cleanup; compare shipped schema downloads against current generated sources, reject obsolete module routes, and search rendered pages and search data for retired terminology. Confirm publication separately from a successful source merge. Historical review text must not reintroduce syntax the user explicitly requested removing.

### Diagnostics are `<cause>; <fix>`, and tools key on the cause

Verified: agents act on a diagnostic only when it names the cause, the location, and a concrete fix (nearest name, import line, valid options). Messages therefore read `<cause>; <fix>`. A diagnostic's rule code classifies only the text before the first `; `, so fix text cannot change a rule code. Partial parsing recovers from an unterminated delimiter by matching the message prefix, and the lexer reports it at end of file; moving that position or exact wording breaks editor recovery. A follow-on error that only restates `<invalid>` after an unknown name or operand mismatch is suppressed, but a genuine mismatch that mentions `<invalid>` (callback arity) must still surface.

Apply when: adding or rewording any lexer, parser, checker, project, compiler, CLI, or runtime message.
Evidence: [message-shape rule](../documentation/developer-tooling/source/diagnostics.md), [code classification](../crates/ms-syntax/src/diag.rs), [checker hints](../crates/ms-check/src/hints.rs), [recovery](../crates/ms-syntax/src/partial.rs).
Verify: run `cargo nextest run -p ms-syntax -p ms-check -p ms-lsp -p ms-cli` and `make conform` (check-phase fixtures compare code, phase, message, and position); extend the hint tests with the new message.

### Standard-library prose has the same owner as declarations

Decision: the user requires `.ms` standard-library sources to own all library documentation. Guide and special-call-rule comment blocks ship with the sources; generated Markdown is disposable and lives under `.artifacts/docs/`. Keep existing routes when moving prose. API contracts belong with their `.ms` modules.

Apply when: changing library docs or the book pipeline.
Evidence: [docgen](../crates/ms-tooling/src/guide/docgen.rs), [docgen binary](../crates/ms-tooling/src/bin/ms-docgen.rs), [Makefile docs targets](../Makefile).
Verify: `make docs-check` works without generated Markdown; `make book-check` generates the mounted pages and validates routes and downloads.

### Agent help is CLI commands, not a protocol server

Decision: the user evaluated an MCP server (PR #528), judged the CLI the better surface for coding agents, and had it removed. Agents with a shell already get compact output from `check`, `lint`, `fmt`, and `test`; the gaps became `ms search_symbol` and `ms guide`. Navigation is by name, not `file:line:col`, because agents track names better than positions; `ms search_symbol` wraps workspace symbols, definition and references, and the next language-server feature to expose is a checked rename. A bare `ms search` read as generic and `ms guide stdlib <module>` printed 42 KB for the prelude, so library lookup folded into `ms search_symbol` (names and words search project and library; a lone module or `<module>[.Decl[.member]]` path shows a page) and every page has a byte budget. Keep the command set small and useful. Search is fuzzy, the guide stays short because agents reread it, and pages are built from the standard declarations, never from `ms doc` or `ms stdlib` (both removed).

Verified: bounded search output does not bound analysis work. Filtering only after enumerating every checked workspace declaration made `search_symbol "read file"` take seconds across the repository fixtures. Apply the same name predicate before checking sources, using lexical matches only as a conservative candidate filter; return checked identities and retain local imports because their graphs can contribute unwritten names. Private module functions and constants cannot be imported, so their references already exist in the selected analysis and need no workspace scan. Preserve reference ordering and exported cross-file uses.

Apply when: adding agent-facing commands, changing search ranking, or touching the cheat sheet or standard-library index.
Evidence: [search](../crates/ms-tooling/src/guide/search.rs), [workspace queries](../crates/ms-lsp/src/workspace.rs), [project search regressions](../crates/ms-lsp/tests/search_symbol.rs), [guide](../crates/ms-tooling/data/cheatsheet.md), [search_symbol CLI tests](../crates/ms-cli/tests/search_symbol.rs), [agent commands](../documentation/developer-tooling/implementation.md#commands-for-agents).
Verify: `cargo nextest run -p ms-lsp -p ms-tooling -p ms-cli`; search tests pin typo, synonym, partial, and dedup behavior; compare release timings and output for project, standard-library and no-match queries in a large source tree. The cheat sheet's program must check and stay short.

### Public positioning is evidence-led: every claim names a committed, reproducible number

Decision: make the case through shipped benefits and measured evidence. The user's October 27 correction—"readme is so text heavy the actual points are getting missed"—supersedes the earlier request to put detailed benchmark tables in the README. Use a concise opening, visibly separated reasons to try Manuscript, one natural example, a quick start and links. Detailed measurements belong in the existing `bench/perf` and `bench/agent` result pages, including unfavorable outcomes, revisions, machines and reproduction commands. Any numeric public claim still cites its particular dated evidence; add new runs rather than rewriting old numbers. Present a batteries-included environment as direction, and keep process history and implementation inventories out of the opening.

Apply when: revising the README, landing page, `why-manuscript`, or the vision's status section, or when a benchmark result is cited anywhere public.
Evidence: the user's October 27 README correction; [README](../README.md#why-manuscript), [measurements](../README.md#see-the-measurements), [why Manuscript](../documentation/learn/why-manuscript.md), [landing shortcode](../website/layouts/_shortcodes/docs-home.html), [perf index](../bench/perf/README.md).
Verify: compare the README's opening, word count, outline and desktop/mobile render with the base branch; the reasons to try Manuscript should be visible before long examples or evidence. Check that every retained number resolves to its dated source, examples pass `ms check` or `ms test`, and `make docs-check` and `make repo-check` pass.

Verified: a result page can contain several revisions and reruns with different outcomes. The October 21 agent run passed 9/10 small challenges; the October 22 compact-guide run passed 10/10 and its terse rerun 9/10. The earliest HTTP table predates whole-file I/O offload, while the dated October 25 table includes a higher post-load memory cost. Cite the particular dated section and its tradeoffs rather than carrying an old explanation forward as current behavior. Evidence: [October 21](../bench/agent/results/summary-2026-10-21.md), [October 22](../bench/agent/results/summary-2026-10-22.md), [dated HTTP results](../bench/perf/web/results.md#2026-10-25). Verify the prose against the whole cited section, including reruns and slower rows.

### Agents get machine-applicable fixes, structured faults and named replacements

Decision: diagnostics carry a `fix` field when the repair is mechanical (nearest-name misspellings, missing imports), and `ms check --fix` / `ms lint --fix` apply them in place and report what remains (no `--watch`). `ms run --json` and `ms test --json` report a runtime fault as data (versioned result with the fault location) instead of text on stderr. Habits from TypeScript, Go and Rust get a named replacement in the diagnostic (`unwrap`/`expect`/`unwrap_or` point to `get(default)`, `if let` or `try`; `len`, `Some`, `Ok`, `parseInt`, `for (...)`, `Int("1")`; any camelCase member maps to snake_case; mixing Int and Float says `to_float()` or `truncate_to_int()`). Known gap: `for (let i = 0; ...; i++)` reports the `;` error first because the lexer fires before the parser.

Apply when: adding or rewording diagnostics, or changing JSON output.
Evidence: [CLI help](../crates/ms-cli/src/help_text.rs), [diagnostics](../documentation/developer-tooling/source/diagnostics.md), [fault report](../crates/ms-cli/src/fault.rs).
Verify: a misspelled name is fixed by `ms check --fix`; `ms run --json` on a faulting program exits with a JSON fault; each new hint has a test and a re-recorded golden.
