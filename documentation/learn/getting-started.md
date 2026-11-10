+++
title = "Run your first program"
weight = 1
aliases = ["/getting-started/"]
+++

# Run your first program

Create a project, run it, change it, and build a native executable. `ms` includes the compiler, standard library, formatter, and test runner.

## 1. Get the compiler and run

For the latest implementation, [build from source](https://github.com/manuscript-lang/manuscript/blob/main/documentation/contributing/rust-toolchain.md#build-and-run) with `make build`. Alternatively, extract a [release archive](https://github.com/manuscript-lang/manuscript/releases) for your operating system and architecture.

Add the directory containing the compiler to your `PATH`: the checkout's `target/release` directory for a source build, or the extracted archive directory. Use the full path to that directory so the command still works after changing directories. On Windows, the compiler is `ms.exe`. Open a new terminal if your PATH settings require it, then confirm:

```sh
ms --version
```

From the directory where you want to keep your project, run:

```sh
ms init my-app
cd my-app
ms run ms.toml -- first second
```

`ms run` compiles `src/main.ms` and prints:

```text
Arguments: 2
```

Values after `--` are the program's arguments. `init` creates `ms.toml`, `src/main.ms`, a test file and a `.gitignore`. Run the remaining commands from `my-app`; there, `ms run -- first second`, `ms check` and `ms test` default to `ms.toml`.

## 2. Read the code {#read-the-program}

Open `src/main.ms`:

<!-- manuscript-example: {"mode":"run","args":["first","second"],"stdout":"Arguments: 2\n"} -->
```manuscript {filename="src/main.ms"}
import arguments from "@std/os/env.ms"

fn main() Unit:
    print("Arguments: {arguments().length()}")
```

- `import … from "…"` selects the APIs the file uses.
- `main` starts the program. It returns `Unit`, `Unit!` (an error prints `error: <message>` and exits 1), `Int?!` (also an exit status), or `Int`; `export` is optional.
- `print` writes a line and needs no import; `{...}` interpolates into strings.
- One tab (or four spaces) opens a block; statements need no terminator.

`print` never fails. See [print a line](../cookbook/command-line.md#print-a-line) for output and error handling.

## 3. Make it yours

Replace the `print` line with:

```manuscript
    print("Hello! You passed {arguments().length()} arguments.")
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

```text
Hello! You passed 2 arguments.
```

On Windows, use `ms build ms.toml -o hello.exe`, then `.\hello.exe first second`. It prints the same greeting and runs without `ms` installed. See [build levels](../developer-tooling/builds/build-levels.md) for debug builds.

## 5. Check and test your project {#create-your-own-project}

Run the generated test and check your changes:

```sh
ms check ms.toml
ms fmt ms.toml
ms test ms.toml
```

For this generated project, the commands report:

```text
Checked ms.toml (2 modules)
RUN test.ms::arithmetic
PASS test.ms::arithmetic
1 tests, 0 failed
```

`fmt` succeeds silently. `check` finds errors without running, `fmt` formats, and `test` runs the generated test block. `ms verify ms.toml` checks source, checks formatting without rewriting files, lints, and runs tests; `ms --help` lists all commands. See [project configuration](../developer-tooling/builds/project-configuration.md) when you need to change the entry point or add dependencies.

## 6. Explore your program

```sh
ms diagram ms.toml --format html -o code-map.html
```

The command succeeds silently and writes `code-map.html`. Open it in a browser to follow calls, read the source and inspect checked types. The interactive file works offline and grows with your project. See [the interactive code map](../developer-tooling/implementation.md#interactive-code-map) for navigation and change overlays.

## Compiler versions and setup

Manuscript is in alpha. These guides follow `main`; for a published release, use the documentation in its source tag. [Build current source](https://github.com/manuscript-lang/manuscript/blob/main/documentation/contributing/rust-toolchain.md#build-and-run) to try the latest features. For a preconfigured or disconnected build environment, see [build tools and local setup](../developer-tooling/how-it-works.md#build-tools-and-local-setup).

## Keep going

Next: the [guide](../guide/_index.md), then [testing](testing.md) and [cookbook](../cookbook/_index.md). For editors, see [developer tools](../developer-tooling/implementation.md).
