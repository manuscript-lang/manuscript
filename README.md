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

Records and alternatives use `type`; operation contracts use `interface`. Generic parameters and bounds belong to type, interface, and named function declarations. An implementation uses those declarations, for example `impl ReadValue[T] for Box[T]:`.

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
| `cmd/ms` | Check, build, emit, run, test, fmt, inspect, diagram, and lock commands |
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

## Read the design book

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

Hugo Book v13 is vendored in `themes/hugo-book/`, including its MIT license. The exact upstream revision is recorded in `themes/hugo-book/UPSTREAM`.

## CI/CD

[The GitHub Actions pipeline](.github/workflows/cicd.yml) builds the design book on branch pushes and pull requests using Hugo Extended 0.146.7. Pushes that only change generated `docs/` files are skipped. Warnings and broken Markdown page links fail the build. The theme is vendored, so no submodule setup is needed.

The pipeline also calls [the language checks](.github/workflows/test-language.yml) with Go 1.25.1: formatting, vet, unit and native end-to-end tests, race checks, and a CLI build and example run. Deployment requires both the book build and language checks to pass. The language workflow can also be run independently from the Actions tab.

After validation succeeds on the repository's default branch (`main`), the pipeline builds with the GitHub Pages URL, commits the generated `docs/` files to that branch, and explicitly requests a Pages build. This request is needed because pushes made with `GITHUB_TOKEN` do not trigger Pages builds automatically. Pull requests and other branches only run validation. You can also run the pipeline manually from the Actions tab; publishing still requires the default branch. Outdated runs skip publishing, and a concurrent branch update causes the push to fail rather than overwrite newer work.

Keep **Settings → Pages → Source** set to **Deploy from a branch**, with **main** and **/docs** selected. The workflow uses the built-in `GITHUB_TOKEN` with contents and Pages write permissions; no deployment secrets are required. Repository rules must allow the workflow to push generated documentation to `main`. If branch protection blocks that push, regenerate and merge `docs/` through a pull request instead. For a custom domain, configure it in Pages settings and update `baseURL` in `hugo.toml` before rebuilding the committed output; CI uses the URL reported by Pages.

For branch protection, require the **Build design book** and **Language checks / test** status checks. To reproduce the book validation locally with Hugo Extended 0.146.7:

```sh
hugo --minify --panicOnWarning --destination /tmp/manuscript-book-validation --baseURL "https://example.org/manuscript/"
```
