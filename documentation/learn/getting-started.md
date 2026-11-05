+++
title = "Run your first program"
weight = 1
aliases = ["/getting-started/"]
+++

# Run your first program

Create a small command-line program, change what it prints, check it, and build an
executable you can run on its own. `ms` includes the compiler, standard library,
formatter, and test runner. You will use the same project throughout this page.

## 1. Get the compiler and run

For the latest implementation, [build from source](../contributing/rust-toolchain.md#build-and-run) with `make build`. Alternatively, extract a [release archive](https://github.com/manuscript-lang/manuscript/releases) for your operating system and architecture.

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

Values after `--` are the program's arguments. `init` creates `ms.toml`, `src/main.ms`, a test file and a `.gitignore`. Run the remaining commands from `my-app`.

## 2. Read the code {#read-the-program}

Open `src/main.ms` and replace it with this version, which also prints a failure message:

<!-- manuscript-example: {"mode":"run","args":["first","second"],"stdout":"Arguments: 2\n"} -->
```manuscript {filename="src/main.ms"}
import arguments from "@std/os/process.ms"
import stdout from "@std/io/io.ms"

export fn main() Int:
    let message = "Arguments: {arguments().length()}\n"
    let outcome = stdout().write(message).map_error(fn cause: print(cause.message))
    if let _written = outcome:
        return 0
    return 1
```

Read the program from its entry point, `main`. `arguments()` supplies the values
passed after `--`; `.length()` counts them. The `let` declaration names a string,
and `{arguments().length()}` inserts the count into that text. The compiler infers
that `message` has type `String` from the value assigned to it.

The imports select the operations this module uses. `stdout().write(message)`
writes the text; its stream API returns a `Result`. `map_error` calls the supplied
function only on failure, printing its message. `if let` takes the success branch;
the remaining path returns the failure status. Returning `1` reports failure
to the shell; returning `0` reports
success. The returned integer is an exit status, not text to print. Four spaces
indent a block, and statements need no terminator.

For simple output, use `print("Hello, Manuscript!")` without an import. See [print a line](common-tasks.md#print-a-line) for output and error handling.

## 3. Make it yours

Replace the `let message` line with:

<!-- manuscript-artifact: {"kind":"edit"} -->
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

`ms run` uses your saved source on each invocation. Changing the string changes
what the program does; changing the command's arguments changes its input. Try
running without `-- first second`: the greeting reports zero arguments. This is
the basic edit-and-run loop you will use while learning the language.

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

Running the program checks one visible behavior. The compiler can also check the
source without executing it, and a test can compare a computed value with an
expected one. Run these commands on the project:

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

Manuscript is in alpha. These guides follow `main`; for a published release, use the documentation in its source tag. [Build current source](../contributing/rust-toolchain.md#build-and-run) to try the latest features. For a preconfigured or disconnected build environment, see [build tools and local setup](../developer-tooling/how-it-works.md#build-tools-and-local-setup).

## Keep going

Next: the [language tour](tour.md), then [testing](testing.md) and [task recipes](common-tasks.md). For editors, see [developer tools](../developer-tooling/implementation.md).
