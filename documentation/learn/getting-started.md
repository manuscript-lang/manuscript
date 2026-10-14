+++
title = "Get started"
weight = 1
aliases = ["/getting-started/"]
+++

# Get started

Download and extract the [Manuscript release archive](https://github.com/manuscript-lang/manuscript/releases) for your operating system and architecture. It includes the `ms` executable, build tools, and examples. You can put `ms` on `PATH` to use it from any directory.

Run these commands from the extracted directory. In Windows PowerShell, replace `./ms` with `.\ms.exe`.

```sh
./ms check examples/hello/ms.toml
./ms run examples/hello/ms.toml -- first second
```

The program prints:

```text
Arguments: 2
```

`check` validates source without running it. `lock` records the project's compiler, runtime, build-tool, and target versions; rerun it after changing those inputs. `run` builds and runs the program, passing it the arguments after `--`.

From a source checkout, run `make build` first. See [development setup](../contributing/development.md) for prerequisites.

## Read the program

The hello project's `src/main.ms` is a complete application:

<!-- manuscript-example: {"mode":"run","args":["first","second"],"stdout":"Arguments: 2\n"} -->
```manuscript
import arguments from "@std/cli.ms"
import stdout from "@std/io.ms"

export fn main() -> Int:
    let message = "Arguments: {arguments().length()}\n"
    match stdout().write(data: message.to_bytes()):
        ok(_):
            return 0
        error(_):
            return 1
```

- `import` selects the argument and standard-output functions this file uses.
- `export fn main() -> Int` defines the application's entry function. Its returned integer becomes the exit code.
- `let` names a value and infers its type. The string inserts the argument count inside `{...}` and ends with a newline, `\n`.
- `stdout().write(data: ...)` writes bytes, so `to_bytes()` converts the text first.
- `write` returns a `Result`. The `match` handles both outcomes: success returns `0`, and failure returns `1`. `_` ignores the outcome's payload.

Four spaces start each nested block. Function calls accept positional arguments; labels are optional and can make a call clearer.

## Understand the project

Each `.ms` file is a module. The `examples/hello/ms.toml` manifest selects the source directory and entry module:

```toml
[project]
name = "hello"
source = "./src"
entry = "./src/main.ms"
```

Paths are relative to the manifest. See [project configuration](../developer-tooling/builds/project-configuration.md) when setting up your own application.

## Create your own project

```sh
ms init hello
cd hello
ms run ms.toml -- first second
ms test ms.toml
```

`ms init [directory]` writes `ms.toml`, `src/main.ms` (the program above), `test.ms`, and a `.gitignore`. It stops without writing anything if one of those files already exists. A project is just that manifest plus an entry module exporting `main() -> Int`, so you can also create the files by hand.

The first `ms run` or `ms build` writes `ms.lock` next to `ms.toml`. It records the compiler, runtime, and toolchain pins the build used: commit it. Earlier versions also wrote a `.ms-cache/` of executables (`ms init` still ignores it); it is safe to delete. A `ms` built from a source checkout has different pins than a release, so running `ms lock` or `ms run` on a project such as `examples/hello` with it rewrites the checked-in `ms.lock`; discard that change rather than committing it.

## Build and test

```sh
./ms build examples/hello/ms.toml -o hello
./hello first second
./ms test examples/hello/test.ms
./ms fmt examples/hello/src/main.ms --check
```

`build` leaves a native executable that runs independently of Manuscript. `test` runs test blocks in the given module, with the project directory (the one holding `ms.toml`, or the test file's directory for a single file) as the working directory, so fixtures such as `golden/input.txt` resolve the same wherever you invoke `ms`; `ms test ms.toml` also runs every `test.ms` and `*_test.ms` file in the project. Each test prints `RUN` before it starts; a test that exceeds `--timeout` (default 60s, `0` disables) fails by name, and `--filter text` runs only tests whose `module::name` contains the text. `fmt --check` reports formatting changes without writing them. Use `./ms --help` to list commands or `./ms help run` for a command's options.

Continue with [the language tour](tour.md). The [developer tools](../developer-tooling/implementation.md) cover editor setup, inspection, API documentation, and debugging.
