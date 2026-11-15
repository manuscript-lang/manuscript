# Changelog

Each release lists what changed for people who write Manuscript. Before 1.0, a change that breaks existing programs ships in a minor release and names its migration; patch releases stay compatible. See [what is frozen before 1.0](documentation/learn/stability.md).

## 0.1.0 (first public release)

The first release. It ships one binary, `ms`, for Linux, macOS and Windows on amd64 and arm64.

### Language

- Statically typed, indentation-based syntax. `x := value` binds immutably, `var x = value` binds a mutable name.
- One owner per value, with no garbage collector and no reference counts. Borrowing is the default, `.clone()` is the only copy, and resources close at the end of their scope.
- Failure is a value: `T!` is a result, `T?` is an optional, and `?` passes a failure up.
- Enums, interfaces matched by shape, generics, pattern matching, and promises that run across all cores.
- A function's effects (files, network, processes) are tracked and checked by the compiler.
- Compiler errors name the fix. `ms check --fix` applies the mechanical ones, and `--json` gives the same diagnostics as data.
- Removed spellings fail with an error that names the replacement, kept for two minor releases. See [removed spellings](documentation/learn/removed-spellings.md).

### Standard library

- Core collections, text, math, time, random numbers, big and decimal numbers.
- Files, processes, environment, and terminal access.
- TCP, HTTP/1.1, HTTP/2, WebSocket and TLS.
- JSON, YAML, TOML, CSV, XML and HTML, with decoders generated per type at compile time.
- Crypto, regular expressions, archives, images, logging and testing.

### Tooling

- `ms run`, `ms build`, `ms check`, `ms test`, `ms fmt` and `ms init`, with native executables from Cranelift (debug) or LLVM (release).
- `ms test --fuzz`, `ms bench` and `ms profile`.
- `ms diagram` and `ms review` show what an agent built and what changed.
- `ms skill` installs the writing guide that agents read.
- A language server and a VS Code extension.

### Install

Run `curl -fsSL https://manuscript-lang.github.io/manuscript/install.sh | sh`, or on Windows `irm https://manuscript-lang.github.io/manuscript/install.ps1 | iex`. Archives and checksums are on the [releases page](https://github.com/manuscript-lang/manuscript/releases).
