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

### Docs CI and GitHub Pages

The `Docs` workflow (`.github/workflows/cicd.yml`) builds the book on branch pushes, pull requests, and manual runs with Hugo Extended 0.146.7. Warnings, broken generated local links, missing anchors, and missing linked assets fail validation. External websites are not checked. The `Language` workflow (`test-language.yml`) continues to test the compiler independently.

To reproduce docs validation with Hugo Extended 0.146.7 and Python 3.9 or newer:

```sh
hugo --gc --minify --panicOnWarning --baseURL https://manuscript-lang.github.io/manuscript/
python3 scripts/check-docs-links.py public https://manuscript-lang.github.io/manuscript/
```

Before the first deployment, a repository administrator must select **Settings → Pages → Build and deployment → Source: GitHub Actions**. Ensure the `github-pages` environment permits deployments from the default branch (currently `main`); any configured approval rules still apply. See [Hugo's GitHub Pages guide](https://gohugo.io/host-and-deploy/deploy-to-github-pages/).

After merge, a default-branch push builds and deploys the book. To rebuild manually, select **Actions → Docs → Run workflow** and choose the default branch. Other branches and PRs validate only, without uploading or deploying a Pages artifact. The deployment build reads the configured Pages URL, including any custom domain, and overrides the local preview URL in `hugo.toml`. Pages must already be enabled for that step; the workflow does not enable it or change repository settings.

Only the deploy job receives `pages: write` and `id-token: write`; the build job has read-only repository and Pages access. No personal access token or `gh-pages` branch is needed, and `public/` remains untracked.
