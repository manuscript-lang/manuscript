+++
title = "Build and share a program"
weight = 1
+++

# Build and share a program

Use `ms run` while changing a program, then `ms build` to produce an executable you can run or share. The recipient needs the matching operating system and architecture, but does not need `ms` installed.

## Check and run your project

Start from a fresh project so you can try the complete workflow:

```sh
ms init my-app
cd my-app
ms check ms.toml
ms run ms.toml --build-type Debug -- first second
```

The check and run report:

```text
Checked ms.toml (2 modules)
Arguments: 2
```

`check` catches source errors without running the application. `run` builds and starts it; arguments after `--` go to your program. `Debug` keeps the edit/run cycle quick. Use `ms run ms.toml --watch -- first second` to rebuild after saved changes, or [set up your editor](implementation.md) for diagnostics while you type.

## Build the executable

```sh
ms build ms.toml -o my-app
./my-app first second
```

```text
Built my-app
Arguments: 2
```

On Windows, name the output `my-app.exe` and run `.\my-app.exe first second`. `ms build` defaults to optimized `Release` (`ms run` and `ms test` default to `Debug`, built with Cranelift); choose [a build level](builds/build-levels.md) when you need unoptimized debugging or a smaller executable.

Share the executable for the platform you built on. On Linux, the default target uses glibc 2.28 or newer. Use `ms build ms.toml --static -o my-app` for a self-contained musl executable; see [platform linking](https://github.com/manuscript-lang/manuscript/blob/main/documentation/contributing/rust-toolchain.md#platform-linking) for supported targets. Files your program opens by path remain external: distribute them with the program, or [embed assets](builds/project-configuration.md#embedded-files) in the executable.

The adjacent `my-app.ms-build.json` holds the compiler version, build level and backend; it is not needed to run the executable. Its `backend` is `llvm` when LLVM compiled the program's functions, or `cranelift` otherwise. A cached build retains the backend that produced the stored executable. Keep source and debug artifacts when you want to [investigate a profile or debug source lines](debugging/debugger-integration.md).

## Check a change before sharing it {#one-binary}

```sh
ms verify ms.toml
ms diagram ms.toml --format html -o code-map.html
```

For the generated project, `verify` reports:

```text
check  passed
fmt    passed
lint   passed
test   passed
```

`verify` checks types, formatting, lint and tests; fix a failed check before building the version you intend to share. It does not rewrite formatting. The second command succeeds silently and writes an offline HTML map: open `code-map.html` to follow source, checked types and calls during review. See [the code-map workflow](implementation.md#interactive-code-map) for change overlays.

The same compiler includes the standard library, formatter, linter, language server and analysis tools. Source-only commands such as `check`, `fmt`, `lint` and `diagram` need no native linker. For a repeatable team setup, use the same `ms` version and keep `ms.toml` with your source.

## Build tools and local setup

Native builds use `lld` to link the executable. Optimized builds also use LLVM tools when available. `ms` uses explicitly configured local tools first, then complete cached tools; it downloads missing tools from pinned releases and verifies their SHA-256 hashes.

| Tool | Local setting | Cache |
| --- | --- | --- |
| Linker | `MS_LLD`: path to a compatible `lld` executable | `<cache>/ms/lld/` |
| LLVM optimization | `MS_LLVM_TOOLS`: directory containing `opt`, `llc` and `llvm-link` | `<cache>/ms/llvm/` |

To avoid these tool downloads, provision the local tools or populate the matching caches beforehand. `MS_BACKEND=cranelift` skips LLVM optimization; a working linker is still required. If the LLVM download fails, the build falls back to Cranelift. If the linker is missing and cannot be downloaded, linking fails with guidance to set `MS_LLD`.

See [cache locations](builds/incremental-compilation.md) and [platform linking details](https://github.com/manuscript-lang/manuscript/blob/main/documentation/contributing/rust-toolchain.md#differences-users-can-see). Compiling `ms` itself has separate [source-build prerequisites](https://github.com/manuscript-lang/manuscript/blob/main/documentation/contributing/rust-toolchain.md#build-and-run).

## Rebuild after changes {#runtime-cache}

`ms build` can reuse an unchanged executable. `run`, `test` and `profile` build fresh executables, while reusing installed tools and the extracted runtime archive. You do not need to manage these caches for normal development; use [build caches](builds/incremental-compilation.md) when troubleshooting reuse or choosing cache locations.

For the compiler's internal stages, see the contributor [compilation pipeline](https://github.com/manuscript-lang/manuscript/blob/main/documentation/contributing/compiler/frontend/pipeline.md).
