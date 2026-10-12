# Manuscript

Manuscript is a statically typed language that compiles to Go and runs as a native executable. Its syntax makes function inputs, expected errors, resource cleanup, and concurrent work explicit.

Read the [book index](documentation/_index.md) to choose a topic, or follow [your first program](documentation/getting-started.md) for a walkthrough. The [glossary](documentation/glossary.md) explains terms used in the guide. [Implementation coverage](documentation/implementation.md) lists working features and remaining limits.

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

## Features and limits

The implementation includes nominal types, generics, explicit interfaces, Result errors, lexical cleanup, joined and background work, synchronized state, queues, pools, builders, and explicit CLI/network/subprocess capabilities. Standard declarations live in [stdlib/](stdlib/README.md); the [generated module reference](documentation/standard-library/reference/_index.md) comes from those declarations.

Read [implementation coverage](documentation/implementation.md) before relying on a feature. External adapters, incremental frontend compilation, and some host/tooling APIs remain design work. The [language tour](documentation/learn/tour.md) introduces supported syntax; the [glossary](documentation/glossary.md) explains its terms.

Project native builds require matching `ms.lock` pins. Run `ms lock` after selecting a toolchain or updating the compiler. Release binaries embed their build tools and pinned dependencies. `MANUSCRIPT_GO` selects an explicit alternative, and `MANUSCRIPT_CACHE_DIR` selects the bundled-toolchain cache. See [reproducible builds](documentation/compiler/builds/reproducibility.md) for details.

## Repository map

| Location | Contents |
| --- | --- |
| `syntax/`, `lexer/`, `parser/`, `checker/` | Source model and language frontend |
| `project/` | Manifest validation, aliases, canonical paths, and editor overlays |
| `compiler/` | Module graph, checked Go lowering, native builds, pins, and caches |
| `runtime/`, `stdlib/` | Native implementation and Manuscript standard declarations |
| `tooling/`, `internal/cli/`, `cmd/ms/` | Source tools, LSP, API rendering, and executable entry point |
| `scripts/` | SDK bootstrap, API generation, payload construction, packaging, and distribution checks |
| `documentation/` | Authored language guides, implementation status, and contributor docs |
| `website/` | Hugo configuration, layouts, assets, API downloads, and vendored theme |
| `docs/` | Generated GitHub Pages output; regenerate with `make book` |
| `tests/`, `examples/`, `extensions/` | Conformance/publication checks, runnable projects, and VS Code integration |

The [architecture guide](documentation/contributing/architecture.md) traces the packages and tells you where to make each kind of change. Existing public parser/checker/compiler imports remain available.

## Develop and verify

```sh
make build
make coverage
make race
make check
make fuzz
make book-check
```

See [development and publishing](documentation/contributing/development.md) for prerequisites, generated files, CI, standalone release checks, and documentation versions. The [tooling guide](documentation/developer-tooling/implementation.md) describes lint, LSP, source inspection, native debugging, and profiles; the [VS Code extension](extensions/vscode/README.md) provides editor setup.

Preview the book with Hugo Extended 0.146.7 or newer:

```sh
hugo --source website server --bind 127.0.0.1 --port 4000 --renderToMemory
```

Read the [published book](https://manuscript-lang.github.io/manuscript/). Its language rules and signatures are maintained in `documentation/` and `stdlib/`, respectively.
