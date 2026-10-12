# Manuscript

The [design guide](design/_index.md) describes the Manuscript language, runtime, compiler, and developer tooling.

## Build and run

Install Go 1.25 or newer. The compiler and runtime use only the Go standard library.

```sh
go build -o ms ./cmd/ms
./ms check examples/hello/ms.toml
./ms lock examples/hello/ms.toml
./ms run examples/hello/ms.toml -- first second
# Arguments: 2
./ms build examples/hello/ms.toml -o hello
./ms test tests/e2e/testdata/accept/cl-01.ms
./ms emit examples/hello/ms.toml -o main.go
./ms inspect examples/hello/ms.toml -o inspection.json
./ms diagram examples/hello/ms.toml -o calls.mmd
./ms fmt examples/hello/src/main.ms --check
```

`ms check` reports positioned parse, resolution, and type errors. `ms build` creates a native executable. `ms emit` writes a self-contained Go program, including its runtime, that can be built with `go build main.go`. `ms run` and `ms test` build temporary executables. Set `MANUSCRIPT_GO` to select a Go executable outside `PATH`.

Project native builds require `ms.lock` to match the compiler/runtime and Go toolchain/target. `ms lock` explicitly creates or updates those pins; run it after selecting your toolchain or updating the compiler. Builds verify cached artifacts and write executable/source metadata. `--debug` on build/run/test disables native optimization and inlining. `ms check --json` provides structured diagnostics.

Applications export `fn main(process: Process) -> Int`; standard symbols use explicit imports. Start with [the hello project](examples/hello/src/main.ms), [core language fixtures](tests/e2e/testdata/accept), and [implementation coverage](IMPLEMENTATION.md). The implementation follows the current design on `main`, including cleanup, joined/background work, queues, state/pools, builders, and explicit CLI/HTTP/subprocess capabilities. External adapters, advanced host APIs, structural editing, and debugger integration remain design work; the coverage document lists the limits.

## Packages

| Package | Responsibility |
| --- | --- |
| `syntax` | Syntax tree, patterns, and source diagnostics |
| `lexer` | UTF-8 tokens, exact layout, literals, and interpolation boundaries |
| `parser` | Declarations, types, named calls, expressions, and suites |
| `checker` | Modules, nominal types, inference, contracts, bounds, captures, control flow, and effects |
| `compiler` | Project loading, checked Go lowering, native builds, pins, caches, and build metadata |
| `runtime` | Values, data/services, cleanup, concurrency, and explicit host capabilities |
| `tooling` | Validated formatting, source inspection, and static diagrams |
| `cmd/ms` | Check, build, emit, run, test, fmt, inspect, diagram, doc, and lock commands |
| `tests/e2e` | Syntax fixtures compiled to native executables and observable runtime expectations |

Embedders can use `parser.Parse`, `checker.Check`, `compiler.CompileSource`, `compiler.CompileFile`, `compiler.Standalone`, `compiler.BuildChecked`, `tooling.Format`, and `tooling.Inspect`. `compiler.Build` is the lower-level native build API without project pin validation. Failed checking produces diagnostics and no generated source.

## Development

```sh
go test ./...
go test -race ./runtime ./checker ./compiler ./tooling
go vet ./...
# Optional parser/compiler robustness checks:
go test ./parser -run '^$' -fuzz FuzzParse -fuzztime 10s
go test ./compiler -run '^$' -fuzz FuzzCompile -fuzztime 10s
```

The end-to-end suite needs the Go toolchain on `PATH` or in `MANUSCRIPT_GO`. It builds accepted modules, executes their `test` blocks, verifies rejected variants, exercises CLI commands, and checks evaluation order, cleanup, numeric faults, and signal cancellation. `make check`, `make test`, `make race`, and `make build` provide the same entry points. CI runs formatting checks, vet, the complete suite, and race tests.

## Read the documentation

Start with [the introduction](design/learn/_index.md), [the language tour](design/learn/tour.md), and [the complete module reference](design/standard-library/reference/_index.md).

The Markdown guides are rendered directly with [Hugo](https://gohugo.io/) and the [Hugo Book theme](https://github.com/alex-shpak/hugo-book). Install Hugo Extended 0.146 or newer.

```sh
hugo server --bind 127.0.0.1 --port 4000 --renderToMemory
```

Open <http://localhost:4000> to browse the chapters, search the book, and follow links between concepts. The preview listens only on your computer and reloads when you edit the guides. Mermaid diagrams use the theme's bundled local runtime.

```sh
hugo --minify
```

The static site is generated in `public/`. Hugo reads the Markdown guides in `design/` directly. Chapter indexes use `_index.md`; each page's front matter sets its title and reading-order weight. New Markdown pages appear automatically. Site settings live in `hugo.toml`.

Hugo Book v13 is vendored in `themes/hugo-book/`, including its MIT license. The exact upstream revision is recorded in `themes/hugo-book/UPSTREAM`.

## CI/CD

[The GitHub Actions pipeline](.github/workflows/cicd.yml) builds the design book on every branch push and pull request using Hugo Extended 0.146.7. Warnings and broken Markdown page links fail the build. The theme is vendored, so no submodule setup is needed.

The pipeline also calls [the language checks](.github/workflows/test-language.yml) with Go 1.25.1: formatting, vet, unit and native end-to-end tests, race checks, and a CLI build and example run. Deployment requires both the book build and language checks to pass. The language workflow can also be run independently from the Actions tab.

After validation succeeds on the repository's default branch, the pipeline builds with the GitHub Pages URL and deploys the resulting `public/` artifact. Pull requests and other branches only run validation. You can also run the pipeline manually from the Actions tab; deployment still requires the default branch.

To enable deployment, open the repository's **Settings → Pages** and select **GitHub Actions** as the build source. The workflow uses the built-in `GITHUB_TOKEN` and requires no deployment secrets. If the `github-pages` environment has approval rules, deployment waits for those approvals. For a custom domain, configure it in Pages settings; the production build uses the URL reported by Pages.

For branch protection, require the **Build design book** and **Language checks / test** status checks. To reproduce the book validation locally with Hugo Extended 0.146.7:

```sh
hugo --minify --panicOnWarning --baseURL "https://example.org/manuscript/"
```

## Generate the standard library reference

Run `make docs` from the repository root after changing standard definitions.
`make docs-check` verifies that checked-in outputs match; the Pages workflow runs
this check before validation and deployment.

`cmd/docgen` reads the checker’s standard registry, including service and host
definitions, and discovers native method names from the embedded `nativeMethod` case labels, so the shipped binary needs no source checkout.
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
