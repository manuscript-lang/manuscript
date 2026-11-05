+++
title = "Run your first program"
weight = 1
aliases = ["/getting-started/"]
+++

# Run your first program

Run, change and test a program before reviewing an agent’s edits; Manuscript is in alpha, and syntax and APIs may change.

## 1. Get the compiler and run

[Build current source](../contributing/rust-toolchain.md) or extract a [release archive](https://github.com/manuscript-lang/manuscript/releases), then add its compiler directory to `PATH`.

```sh
ms init my-app
cd my-app
ms run ms.toml -- first second
```

```text
Created project in my-app
Next: ms run my-app/ms.toml -- first second
Arguments: 2
```

- Use the absolute `target/release` directory for a source build; Windows uses `ms.exe`.
- Run the remaining commands inside `my-app`; values after `--` are program arguments.

## 2. Read and change the code {#read-the-program}

<span id="3-make-it-yours"></span>

Replace `src/main.ms` with this complete program.

<!-- manuscript-example: {"mode":"run","filename":"src/main.ms","args":["first","second"],"stdout":"Hello! You passed 2 arguments.\n"} -->
```manuscript {filename="src/main.ms"}
import arguments from "@std/os/process.ms"

export fn main() Int:
    let count = arguments().length()
    print("Hello! You passed {count} arguments.")
    return 0
```

```sh
ms run src/main.ms -- first second
```

```text
Hello! You passed 2 arguments.
```

- `let` fixes a binding; `{count}` inserts its value into text.
- `print` is in the prelude; `main` returns the exit status.

## 3. Build something you can share {#build-and-test}

```sh
ms build ms.toml -o hello
./hello first second
```

```text
Built hello
Hello! You passed 2 arguments.
```

- On Windows, build with `-o hello.exe` and run `.\hello.exe first second`.
- Build for the recipient’s OS and architecture; no installed `ms` is needed. Choose a [build level](../developer-tooling/builds/build-levels.md).

## 4. Check and test your project {#create-your-own-project}

```sh
ms check ms.toml
ms fmt ms.toml
ms test ms.toml
```

```text
Checked ms.toml (2 modules)
RUN test.ms::arithmetic
PASS test.ms::arithmetic
1 tests, 0 failed
```

- `fmt` succeeds silently and formats source.
- `ms verify ms.toml` combines type, formatting, lint and test checks without rewriting files.

## 5. Explore your program {#6-explore-your-program}

```sh
ms diagram ms.toml --format html -o code-map.html
```

- Succeeds silently and writes `code-map.html`; open it to follow source, types and calls offline.
- Use the [code map](../developer-tooling/implementation.md#interactive-code-map) when reviewing a change.

## Compiler versions and setup

- These guides follow `main`; use a release’s source-tag documentation with that release.
- See [local build-tool setup](../developer-tooling/how-it-works.md#build-tools-and-local-setup) for preconfigured or disconnected environments.

## Keep going

Next: [language tour](tour.md), [testing](testing.md), [task recipes](common-tasks.md).
