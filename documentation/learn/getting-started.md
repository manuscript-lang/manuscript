+++
title = "Run your first program"
weight = 1
aliases = ["/getting-started/"]
+++

# Run your first program

Create a project, run it, change it, and build a native executable. `ms` includes the compiler, standard library, formatter, and test runner.

Manuscript is in alpha. These guides follow the source on `main`. A published release can lag behind it; consult the documentation in your release's source tag, or [build current source](../contributing/rust-toolchain.md#build-and-run) to try the latest features.

## 1. Get the compiler and run

For the latest implementation, [build from source](../contributing/rust-toolchain.md#build-and-run) with `make build`. Alternatively, extract a [release archive](https://github.com/manuscript-lang/manuscript/releases) for your operating system and architecture.

Add the directory containing the compiler to your `PATH`: the checkout's `target/release` directory for a source build, or the extracted archive directory. Use the full path to that directory so the command still works after changing directories. On Windows, the compiler is `ms.exe`. Open a new terminal if your PATH settings require it, then confirm:

```sh
ms --version
```

Keep an Internet connection for the first build: `ms` downloads a pinned linker into its cache, and Release builds also fetch LLVM tools. Subsequent builds reuse them. For local tool overrides and platform requirements, see [the toolchain guide](../contributing/rust-toolchain.md#differences-users-can-see).

From the directory where you want to keep your project, run:

```sh
ms init my-app
cd my-app
ms run ms.toml -- first second
```

The first run prepares the build tools, compiles `src/main.ms`, then prints:

```text
Arguments: 2
```

Values after `--` are the program's arguments. `init` creates `ms.toml`, `src/main.ms`, a test file and a `.gitignore`. Run the remaining commands from `my-app`.

## 2. Read the code {#read-the-program}

Open `src/main.ms`:

<!-- manuscript-example: {"mode":"run","args":["first","second"],"stdout":"Arguments: 2\n"} -->
```manuscript {filename="src/main.ms"}
import arguments from "@std/os/process.ms"
import stdout from "@std/io/io.ms"

export fn main() Int:
    let message = "Arguments: {arguments().length()}\n"
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
    let message = "Hello! You passed {arguments().length()} arguments.\n"
```

Save the file and run the same command again:

```sh
ms run ms.toml -- first second
```

```text
Hello! You passed 2 arguments.
```

`ms run` rebuilds from your saved source every time.

## 4. Build something you can share {#build-and-test}

```sh
ms build ms.toml -o hello
./hello first second
```

On Windows, use `ms build ms.toml -o hello.exe`, then `.\hello.exe first second`. It prints the same greeting and runs without `ms` installed. See [build levels](../developer-tooling/builds/build-levels.md) for debug builds.

## 5. Check and test your project {#create-your-own-project}

Run the generated test and check your changes:

```sh
ms check ms.toml
ms fmt ms.toml
ms test ms.toml
```

`check` finds errors without running, `fmt` formats, and `test` runs the generated test block. `ms verify` runs check, fmt, lint, and test; `ms --help` lists all commands. See [project configuration](../developer-tooling/builds/project-configuration.md) when you need to change the entry point or add dependencies.

## Keep going

Next: the [language tour](tour.md), then [testing](testing.md) and [task recipes](common-tasks.md). For editors, see [developer tools](../developer-tooling/implementation.md).
