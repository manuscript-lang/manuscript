# Changelog

Each release lists what changed for people who write Manuscript. Versions are dates (`YYYY.MM.PATCH`). See [what is frozen](documentation/core-language/stability.md).

## Unreleased

### Standard library

- `Iterable` and `for` over it are removed. `Deque`, `Queue` and `PriorityQueue` read by position: `get(index)` returns an optional, and a negative index counts from the end. Walk one with `for i in 0..q.length()`.
- `Result.error` is removed. Check `is_error()` and read the cause with `err()`.
- `Url.query` is a `String?`: `none` means no query and an empty string means a bare `?`. `has_query` is removed, and `fragment` now comes before `query` in `Url(...)`.
- A bad value from the caller returns instead of crashing. A size, count, radix or budget gives `EINVAL` where the function already returns an `Error`, and `none` where it already returns an optional. `take(0)`, `chunks(0)` and similar give an empty result, and a shift count of 64 or more shifts every bit out. Faults remain for bugs: an index out of range, overflow, a negative shift count. See [choosing a failure](documentation/core-language/errors/_index.md#choosing-a-failure-in-the-standard-library).
- `rate_limiter` returns `RateLimiter!`, `BitSet.add` returns `Void!`, and `to_string_radix` returns `String?`. `to_hex()` and `to_binary()` always succeed, and `to_string()` is base 10.
- `SeededRandom.weighted_choice` returns `none` for weights that do not fit the values.
- Complex: `asin` and `acos` keep every digit for a tiny argument and for a huge real part, and `sqrt` of a number with an infinite imaginary part or a NaN real part follows C99 (infinite, and NaN).
- `fs.exists` returns `false` for a path below a file (`file.txt/child`), as its documentation said. Windows UNC paths (`\\server\share`) now collapse repeated separators in `normalize` and `join`, and a path with three leading separators is no longer read as UNC.
- `String.split` and `Bytes.split` take only the separator: the `max_parts` limit is removed, because it truncated instead of keeping the rest. Drop the second argument; to stop early, loop with `index_of`.

## 2026.11.0 (first public release, beta)

The first release. It ships one binary, `ms`, for Linux, macOS and Windows on amd64 and arm64.

### Language

- Statically typed, indentation-based syntax. `x := value` binds immutably, `var x = value` binds a mutable name.
- One owner per value, with no garbage collector and no reference counts. Borrowing is the default, `.clone()` is the only copy, and resources close at the end of their scope.
- Failure is a value: `T!` is a result, `T?` is an optional, and `?` passes a failure up.
- Enums, interfaces matched by shape, generics, pattern matching, and promises that run across all cores.
- A function's effects (files, network, processes) are tracked and checked by the compiler.
- Compiler errors name the fix. `ms check --fix` applies the mechanical ones, and `--json` gives the same diagnostics as data.
- Removed spellings fail with an error that names the replacement. See [removed spellings](documentation/core-language/removed-spellings.md).

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
