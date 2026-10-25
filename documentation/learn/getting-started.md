+++
title = "Run your first program"
weight = 1
aliases = ["/getting-started/"]
+++

# Run your first program

Run an example, change it, and build a native executable. `ms` includes the compiler, standard library, formatter, and test runner.

Manuscript is in alpha. These guides follow the source on `main`. A published release can lag behind it; consult the documentation in your release's source tag, or [build current source](../contributing/rust-toolchain.md#build-and-run) to try the latest features.

## 1. Get the compiler and run

For the current implementation, [build from source](../contributing/rust-toolchain.md#build-and-run) with `make build`, then use `target/release/ms` in place of `./ms` below. If the [releases page](https://github.com/manuscript-lang/manuscript/releases) provides an archive for your operating system and architecture, you can extract that instead.

Keep an Internet connection for the first build: `ms` downloads a pinned linker into its cache, and Release builds also fetch LLVM tools. Subsequent builds reuse them. For local tool overrides and platform requirements, see [the toolchain guide](../contributing/rust-toolchain.md#differences-users-can-see).

Open a terminal in the checkout root (or the extracted archive directory) and run:

```sh
./ms run examples/hello/ms.toml -- first second
```

On Windows PowerShell, use `.\ms.exe`. The first run prepares the build tools, compiles the example, then prints:

```text
Arguments: 2
```

Values after `--` are the program's arguments. `make build` builds the native runtime before embedding it in the compiler; see [development setup](../contributing/development.md).

## 2. Read the code {#read-the-program}

Open `examples/hello/src/main.ms`:

<!-- manuscript-example: {"mode":"run","args":["first","second"],"stdout":"Arguments: 2\n"} -->
```manuscript {filename="src/main.ms"}
from "@std/process.ms" import arguments
from "@std/io.ms" import stdout

export def main() -> Int:
    let message = f"Arguments: {arguments().length()}\n"
    if stdout().write(message).is_error():
        return 1
    return 0
```

- `from "…" import …` selects the APIs the file uses.
- `main` starts the program; its returned integer is the exit status.
- `let` names a value and infers its type; `{...}` interpolates into strings.
- `write` takes text and returns a `Result`; `is_error()` tests for failure.
- Four spaces open a block; statements need no terminator.

## 3. Make it yours

Replace the `let message` line with:

```manuscript
    let message = f"Hello! You passed {arguments().length()} arguments.\n"
```

Save the file and run the same command again:

```sh
./ms run examples/hello/ms.toml -- first second
```

```text
Hello! You passed 2 arguments.
```

`ms run` rebuilds from your saved source every time.

## 4. Build something you can share {#build-and-test}

```sh
./ms build examples/hello/ms.toml -o hello
./hello first second
```

On Windows, use `.\ms.exe build examples/hello/ms.toml -o hello.exe`, then `.\hello.exe first second`. The executable runs without `ms` installed. See [build levels](../developer-tooling/builds/build-levels.md) for debug builds.

## 5. Start your own project {#create-your-own-project}

Put `ms` on your `PATH`, then run:

```sh
ms init my-app
cd my-app
ms run ms.toml -- first second
ms test ms.toml
```

The new program prints `Arguments: 2`; `ms test` runs the generated test. `init` creates a manifest, `src/main.ms`, a test file, and a `.gitignore`; see [project configuration](../developer-tooling/builds/project-configuration.md). While you work:

```sh
ms check ms.toml
ms fmt ms.toml
ms test ms.toml
```

`check` finds errors without running, `fmt` formats, `test` runs test blocks. `ms verify` runs check, fmt, lint, and test; `ms --help` lists all commands.

## Keep going

Next: the [language tour](tour.md), then [testing](testing.md) and [task recipes](common-tasks.md). For editors, see [developer tools](../developer-tooling/implementation.md).
