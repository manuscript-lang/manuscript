+++
title = "Run your first program"
weight = 1
aliases = ["/getting-started/"]
+++

# Run your first program

Run an example, change what it does, and turn it into a standalone executable.
The release includes `ms`, its build tools, and example projects; you do not need
to install another compiler or runtime.

## 1. Download and run

[Download Manuscript](https://github.com/manuscript-lang/manuscript/releases)
for your operating system and architecture, then extract the archive. Open a
terminal in the extracted directory and run:

```sh
./ms run examples/hello/ms.toml -- first second
```

In Windows PowerShell, use `.\ms.exe` in place of `./ms`.
The first run prepares the bundled build tools, then prints:

```text
Arguments: 2
```

The values after `--` are your program's arguments. `run` builds a temporary
executable and starts it. You have just run your first Manuscript program.

Building from a source checkout? Run `make build` in the repository root first.
[Development setup](../contributing/development.md) lists the prerequisites.

## 2. Read the code {#read-the-program}

Open `examples/hello/src/main.ms`:

<!-- manuscript-example: {"mode":"run","args":["first","second"],"stdout":"Arguments: 2\n"} -->
```manuscript {filename="src/main.ms"}
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

`import` selects the APIs this file uses. The program starts in `main`, and
its returned integer becomes the exit status: `0` for success, `1` for failure.

`let` names a value and infers its type. Inside the string, `{...}` inserts
the argument count and `\n` adds a newline. `stdout().write` takes bytes, so
`to_bytes()` encodes the text. Writing can fail; `match` handles both outcomes.
The `_` ignores a payload we do not need.

Four spaces start a nested block. There is no punctuation to end a statement.

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

Try changing the text or passing a different number of arguments. `ms` rebuilds
from your saved source each time you run it.

## 4. Build something you can share {#build-and-test}

```sh
./ms build examples/hello/ms.toml -o hello
./hello first second
```

On Windows, build with `-o hello.exe` and run `.\hello.exe first second`.
The executable runs on its target operating system and architecture without
`ms` installed. See [build levels](../developer-tooling/builds/build-levels.md)
when you need a debug build.

## 5. Start your own project {#create-your-own-project}

Add the extracted `ms` executable to your `PATH`, then run:

```sh
ms init hello
cd hello
ms run ms.toml -- first second
ms test ms.toml
```

`init` creates a project manifest, `src/main.ms`, a test file, and a `.gitignore`.
The manifest tells `ms` where your source and entry file live.
[Project configuration](../developer-tooling/builds/project-configuration.md)
explains these files when you need to change them.

While you work, use these commands from your new project's directory:

```sh
ms check ms.toml
ms fmt ms.toml
ms test ms.toml
```

`check` catches source errors without running the program, `fmt` formats your
code, and `test` runs its test blocks. `ms verify` runs check, fmt, lint, and
test together. Use `ms --help` to see all commands.

## Keep going

Continue with the [language tour](tour.md) to learn the ideas behind the code.
Then [test your code](testing.md) and try a [task recipe](common-tasks.md).
For editor setup, see [developer tools](../developer-tooling/implementation.md).
