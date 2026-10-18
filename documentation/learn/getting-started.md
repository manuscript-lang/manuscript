+++
title = "Run your first program"
weight = 1
aliases = ["/getting-started/"]
+++

# Run your first program

Run an example, change it, and build a standalone executable. The release bundles `ms`, its build tools, and examples; nothing else to install.

## 1. Download and run

[Download Manuscript](https://github.com/manuscript-lang/manuscript/releases)
and extract the archive. In that directory run:

```sh
./ms run examples/hello/ms.toml -- first second
```

On Windows PowerShell, use `.\ms.exe`. The first run prepares the build tools, then prints:

```text
Arguments: 2
```

Values after `--` are the program's arguments. From a source checkout, run `make build` first ([development setup](../contributing/development.md)).

## 2. Read the code {#read-the-program}

Open `examples/hello/src/main.ms`:

<!-- manuscript-example: {"mode":"run","args":["first","second"],"stdout":"Arguments: 2\n"} -->
```manuscript {filename="src/main.ms"}
import arguments from "@std/process.ms"
import stdout from "@std/io.ms"

export fn main() Int:
    let message = "Arguments: {arguments().length()}\n"
    if stdout().write(message.to_bytes()).is_error():
        return 1
    return 0
```

- `import` selects the APIs the file uses.
- `main` starts the program; its returned integer is the exit status.
- `let` names a value and infers its type; `{...}` interpolates into strings.
- `write` takes bytes and returns a `Result`; `is_error()` tests for failure.
- Four spaces open a block; statements need no terminator.

## 3. Make it yours

Replace the `let message` line with:

```manuscript
    let message = "Hello! You passed {arguments().length()} arguments.\n"
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

On Windows, use `-o hello.exe`. The executable runs without `ms` installed. See [build levels](../developer-tooling/builds/build-levels.md) for debug builds.

## 5. Start your own project {#create-your-own-project}

Put `ms` on your `PATH`, then run:

```sh
ms init hello
cd hello
ms run ms.toml -- first second
ms test ms.toml
```

`init` creates a manifest, `src/main.ms`, a test file, and a `.gitignore`; see [project configuration](../developer-tooling/builds/project-configuration.md). While you work:

```sh
ms check ms.toml
ms fmt ms.toml
ms test ms.toml
```

`check` finds errors without running, `fmt` formats, `test` runs test blocks. `ms verify` runs check, fmt, lint, and test; `ms --help` lists all commands.

## Keep going

Next: the [language tour](tour.md), then [testing](testing.md) and [task recipes](common-tasks.md). For editors, see [developer tools](../developer-tooling/implementation.md).
