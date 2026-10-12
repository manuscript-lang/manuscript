# Manuscript

Manuscript is a statically typed language that compiles to Go and runs as a native executable. Its syntax makes function inputs, expected errors, resource cleanup, and concurrent work explicit.

Read the [book index](design/_index.md) to choose a topic, or follow [your first program](design/getting-started.md) for a walkthrough. The [glossary](design/glossary.md) explains terms used in the guide. [Implementation coverage](IMPLEMENTATION.md) lists working features and remaining limits.

## Get started

Download the archive for your operating system and architecture from
[Releases](https://github.com/manuscript-lang/manuscript/releases), then extract it.
The single `ms` binary includes the native build tools and references it needs.
No separate Go installation or package downloads are needed to build, run, test,
or profile your programs. Copy `ms` (`ms.exe` on Windows) anywhere on `PATH`;
it needs no companion SDK directory.

From a source checkout on macOS or Linux, run `make build`. It downloads and
verifies the pinned Go SDK locally on first use, then builds the self-contained
`./ms`. Initial setup needs Make, curl, tar, and `sha256sum` or `shasum`, plus
Internet access. Later builds reuse `toolchain/go/`.

Run these commands from the extracted archive or repository root. Use `.\ms.exe`
in Windows PowerShell:

```sh
./ms check examples/hello/ms.toml
./ms lock examples/hello/ms.toml
./ms run examples/hello/ms.toml -- first second
```

Expected output:

```text
Arguments: 2
```

`check` validates source without running it. `lock` creates or updates the build pins. `run` builds a temporary executable and passes it the arguments after `--`.

To keep an executable:

```sh
./ms build examples/hello/ms.toml -o hello
./hello first second
./ms test examples/hello/test.ms
```

Applications export `fn main(process: Process) -> Int`. Standard names need explicit imports. See [the hello source](examples/hello/src/main.ms) and [accepted core-language fixtures](tests/e2e/testdata/accept) for complete examples.

## Choose a command

| Task | Example |
| --- | --- |
| Check source and report parse, name, and type errors | `./ms check examples/hello/ms.toml` |
| Get structured diagnostics | `./ms check examples/hello/ms.toml --json` |
| Run a module's tests | `./ms test tests/e2e/testdata/accept/cl-01.ms` |
| Write generated Go | `./ms emit examples/hello/ms.toml -o main.go` |
| Inspect checked source | `./ms inspect examples/hello/ms.toml -o inspection.json` |
| Write a call diagram | `./ms diagram examples/hello/ms.toml -o calls.mmd` |
| Check formatting without writing | `./ms fmt examples/hello/src/main.ms --check` |

`--debug` on build, run, or test disables native optimization and inlining. Native
commands unpack the embedded build payload into the OS user cache on first use
and reuse it thereafter. Set `MANUSCRIPT_CACHE_DIR` to choose another writable
cache directory, or `MANUSCRIPT_GO` to explicitly select another Go executable.
Native builds disable CGO. Developer binaries built directly with `go build` can
use Go on `PATH`; `make build` embeds the payload.

## Build pins and generated Go

Project native builds require `ms.lock` to match the compiler/runtime and Go toolchain/target. Run `ms lock` after selecting a toolchain or updating the compiler. Builds verify cached artifacts and write executable/source metadata.

`ms build`, `run`, and `test` bundle pinned dependencies and require no package downloads. `run` and `test` use temporary executables. The distribution pins and vendors its WebSocket and public-suffix dependencies.

The embedded payload contains the Go build driver, compiler, linker, assembler,
assembly headers, time-zone data, and the standard-library dependency closure
used by Manuscript's runtime for the six supported targets. It excludes Go's
tests, documentation, formatter, and unrelated tools.

`ms emit` writes a Go program containing the Manuscript runtime. Building emitted
source directly requires the repository's pinned `go.mod`, `go.sum`, and `vendor/`
tree. From a source checkout, use `toolchain/go/bin/go build -mod=vendor main.go`.

## Language and implementation

Use `type` for records and alternatives, and `interface` for operation contracts. Generic parameters and bounds belong to type, interface, and named function declarations. An implementation uses those declared parameters, as in `impl ReadValue[T] for Box[T]:`. Implementations for imported source types are [local extensions](design/core-language/types/contracts.md#coherence-and-visibility), visible only in the module declaring them.

The implementation includes cleanup, joined and background work, queues, state and pools, builders, and explicit CLI, HTTP, and subprocess capabilities. External adapters, advanced host APIs, and generalized structural editing still have design work. Check [coverage](IMPLEMENTATION.md) for exact limits.

## Developer tooling

`ms lint`, `ms lsp`, `ms debug`, and `ms profile` provide source hygiene, editor integration, native debugging, and CPU/heap/trace profiling. See the [tooling guide](tooling/README.md), [VS Code extension](extensions/vscode/README.md), and [demo project](examples/tooling-demo/README.md) for installation, supported features, and current limits.

## Packages

| Package | Responsibility |
| --- | --- |
| `syntax` | Syntax tree, patterns, and source diagnostics |
| `lexer` | UTF-8 tokens, exact layout, literals, and interpolation boundaries |
| `parser` | Declarations, types, calls, expressions, and suites |
| `checker` | Modules, nominal types, inference, contracts, bounds, captures, control flow, and effects |
| `compiler` | Project loading, checked Go lowering, native builds, pins, caches, and build metadata |
| `runtime` | Values, data/services, cleanup, concurrency, and explicit host capabilities |
| `tooling` | Formatting, semantic lint, typed LSP completion/navigation/refactoring, source metadata, and static diagrams |
| `cmd/ms` | Check, lint, lsp, profile, debug, build, emit, run, test, fmt, inspect, diagram, doc, stdlib, and lock commands |
| `tests/e2e` | Syntax fixtures compiled to native executables and observable runtime expectations |

Embedders can use `parser.Parse`, `checker.Check`, `compiler.CompileSource`, `compiler.CompileFile`, `compiler.Standalone`, `compiler.BuildChecked`, `tooling.Format`, and `tooling.Inspect`. `compiler.Build` is the lower-level native build API without project pin validation. Failed checking produces diagnostics and no generated source.

## Development

```sh
make test
make race
make check
# Optional parser/compiler robustness checks:
toolchain/go/bin/go test ./parser -run '^$' -fuzz FuzzParse -fuzztime 10s
toolchain/go/bin/go test ./compiler -run '^$' -fuzz FuzzCompile -fuzztime 10s
```

Make prepares and selects the bundled toolchain for the end-to-end suite. It builds accepted modules, executes their `test` blocks, verifies rejected variants, exercises CLI commands, and checks evaluation order, cleanup, numeric faults, and signal cancellation. Race checks additionally require a C compiler. CI runs formatting checks, vet, the complete suite, race tests, and `make dist-check`, which exercises a copied single binary with no Go on `PATH`, empty caches, and package downloads disabled.

`make dist` creates a self-contained archive in `dist/`.
`sh scripts/package.sh <os> <arch>` packages `linux`, `darwin`, or `windows` for
`amd64` or `arm64`. Distributions contain the binary, examples, and license notices.
Update `.go-version` and `scripts/toolchains.sha256` together when upgrading Go.

## Read the documentation

Start with [the introduction](design/learn/_index.md), [the language tour](design/learn/tour.md), and [the complete module reference](design/standard-library/reference/_index.md).

Read the published book at <https://manuscript-lang.github.io/manuscript/>. Changes to `design/` publish automatically after CI passes on `main`.

The Markdown guides are rendered directly with [Hugo](https://gohugo.io/) and the [Hugo Book theme](https://github.com/alex-shpak/hugo-book). Install Hugo Extended 0.146 or newer.

```sh
hugo server --bind 127.0.0.1 --port 4000 --renderToMemory
```

Open <http://localhost:4000> to browse the chapters, search the book, and follow links between concepts. The preview listens only on your computer and reloads when you edit the guides. Mermaid diagrams use the theme's bundled local runtime.

```sh
hugo --minify
```

The static site is generated in `docs/`, which is committed for GitHub Pages to serve. Edit the Markdown guides in `design/`, then rebuild; files in `docs/` are generated output. Chapter indexes use `_index.md`; each page's front matter sets its title and reading-order weight. New Markdown pages appear automatically. Site settings live in `hugo.toml`. The `static/.nojekyll` marker is copied into `docs/` so Pages serves the Hugo output directly.

The root `.msversion` file contains the current documentation version (initially
`0.1.0`, without a `v` prefix). Hugo reads it for the header's version dropdown,
homepage badge, sidebar, and footer. Change this file and rebuild to update all
documentation version labels.

When older documentation is available, add its version and published site URL to
`data/docs_versions.toml` as an `[[archives]]` entry. Relative URLs such as
`versions/v0.1.0/` respect the site's configured base URL; full URLs can point to a
separate docs host. Selecting an archive opens that version's documentation home,
so pages added in newer versions do not produce broken links. The current version
is always included automatically. Archive entries only link to published sites;
they do not create or preserve snapshots. Keep snapshots outside the generated
`docs/` directory, which production builds clean before publishing.

Hugo Book v13 is vendored in `themes/hugo-book/`, including its MIT license. The exact upstream revision is recorded in `themes/hugo-book/UPSTREAM`.

The documentation's visual design lives in `assets/_custom.scss`, with layout and
navigation overrides in `layouts/`. The overview uses the `docs-home` shortcode;
`assets/docs.js` provides theme preferences, copy buttons, and mobile keyboard
controls. Keep site customizations in these files rather than editing the
vendored theme. After a presentation change, rebuild `docs/` with `hugo --minify
--panicOnWarning --cleanDestinationDir`.

Label Manuscript code fences `manuscript`; keep terminal output labeled `text`.
The docs reuse the VS Code extension's grammar in
`extensions/vscode/syntaxes/manuscript.tmLanguage.json`. Change lexical rules
there, then run `node --test tests/docs/highlighting.test.cjs` to check the
browser adapter before rebuilding the site.

## CI/CD

[The GitHub Actions pipeline](.github/workflows/cicd.yml) builds the design book on branch pushes and pull requests using Hugo Extended 0.146.7. Pushes that only change generated `docs/` files are skipped. Warnings and broken Markdown page links fail the build. The theme is vendored, so no submodule setup is needed.

The pipeline also calls [the language checks](.github/workflows/test-language.yml) with Go 1.25.1: formatting, vet, unit and native end-to-end tests, race checks, and a CLI build and example run. Deployment requires both the book build and language checks to pass. The language workflow can also be run independently from the Actions tab.

The [distribution workflow](.github/workflows/release.yml) builds archives for all
six targets and tests their standalone commands on the native OS and architecture.
Manual runs produce Actions artifacts; `v*` tags publish verified archives and
checksums to GitHub Releases.

After validation succeeds on the repository's default branch (`main`), the pipeline builds with the GitHub Pages URL, commits the generated `docs/` files to that branch, and explicitly requests a Pages build. This request is needed because pushes made with `GITHUB_TOKEN` do not trigger Pages builds automatically. Pull requests and other branches only run validation. You can also run the pipeline manually from the Actions tab; publishing still requires the default branch. Outdated runs skip publishing, and a concurrent branch update causes the push to fail rather than overwrite newer work.

Keep **Settings → Pages → Source** set to **Deploy from a branch**, with **main** and **/docs** selected. The workflow uses the built-in `GITHUB_TOKEN` with contents and Pages write permissions; no deployment secrets are required. Repository rules must allow the workflow to push generated documentation to `main`. If branch protection blocks that push, regenerate and merge `docs/` through a pull request instead. For a custom domain, configure it in Pages settings and update `baseURL` in `hugo.toml` before rebuilding the committed output; CI uses the URL reported by Pages.

For branch protection, require the **Build design book** and **Language checks / test** status checks. To reproduce the book validation locally with Hugo Extended 0.146.7:

```sh
hugo --minify --panicOnWarning --destination /tmp/manuscript-book-validation --baseURL "https://example.org/manuscript/"
```

## Generate the standard library reference

Run `make docs` from the repository root after changing standard definitions.
`make docs-check` verifies that checked-in outputs match; the Pages workflow runs
this check before validation and deployment.

`cmd/docgen` reads the checker’s standard registry loaded from the bundled
`stdlib/*.ms` declarations, including intrinsic receiver operations. The shipped
binary needs no source checkout.
It captures checked signatures, generic bounds, fields, cases, and operations
without maintaining a second API catalog. The intrinsic prelude is included.
Special contextual calls and constructors are documented in
[call rules](documentation/call-rules.md), which require review when
`checker/calls.go` changes.

Generated module pages live in `design/standard-library/reference/`. Hugo copies
`static/stdlib.md`, `static/stdlib.json` (schema version 1), and `static/llms.txt`
to the Pages site root. Relative links support repository Pages prefixes and
custom domains. `stdlib.md` contains the entire implemented API in one plain-text
document for LLM ingestion; the JSON has stable sorted modules and declarations.
The existing design chapters explain behavior and identify proposed extensions.

## Generate documentation with ms

The shipped binary includes the documentation generator; no Go installation or
compiler source checkout is required.

```sh
ms doc src/library.ms -o api.md
ms doc ms.toml --json -o api.json
ms doc --stdlib -o stdlib.md
ms doc --stdlib --json -o stdlib.json
```

Without `-o`, documentation is written to stdout. Source modules are checked first;
only their own exported declarations are documented, including fields, cases,
contract operations, and generic bounds. Projects include loaded local modules.
Private declarations and re-imported standard symbols are excluded. The stdlib
reference describes the compiler version bundled with that binary.

`documentation/call-rules.md` is the canonical source for special call rules;
`make docs` also regenerates its page in the design book.
Standard library types and signatures live in [`stdlib/`](stdlib/README.md) as Manuscript source. Editor adapters can resolve their declarations through the tooling navigation APIs; `ms stdlib <directory>` exports the pinned source documents.

Common JavaScript data operations have immutable, typed equivalents on List, String, Map, Set, Bytes, BigInt, and Regex. See the [JavaScript built-in coverage guide](design/standard-library/packages/javascript-builtins.md) for receiver methods, examples, and remaining gaps.
