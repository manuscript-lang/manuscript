+++
title = "Build and share a program"
weight = 1
+++

# Build and share a program

Review the same source you run and ship; save this as `review.ms`.

<!-- manuscript-example: {"mode":"run","stdout":"Ready to review\n","filename":"review.ms"} -->
```manuscript {filename="review.ms"}
export fn main() Int:
    print("Ready to review")
    return 0
```

## Check and run your project

```sh
ms check review.ms
ms run review.ms --build-type Debug
```

```text
Checked review.ms
Ready to review
```

- Replace `review.ms` with `ms.toml` for an existing project; arguments after `--` reach the program.
- Manuscript is in alpha; syntax and APIs may change, so keep the compiler version consistent across reviewers.

## Build the executable

```sh
ms build review.ms -o review
./review
```

```text
Built review
Ready to review
```

- Share with the same operating system and architecture; `ms` is not needed to run it. On Windows use `review.exe` and `.\review.exe`.
- Linux defaults to glibc 2.28+; `--static` builds with musl. Distribute opened files separately or [embed them](builds/project-configuration.md#embedded-files).

## Check a change before sharing it {#one-binary}

```sh
ms verify review.ms
ms diagram review.ms --format html -o code-map.html
```

```text
check  passed
fmt    passed
lint   passed
test   passed
```

- `verify` checks formatting without rewriting it; this file has no tests, so add test blocks for behavioral checks.
- Diagram generation succeeds silently; open `code-map.html` to review checked source, types and calls offline.

## Build tools and local setup

- Native builds reuse cached tools; configure `MS_LLD` and `MS_LLVM_TOOLS` for local tools or offline setup.
- Missing tools may download; unavailable LLVM falls back to Cranelift, but linking needs a linker.

<span id="runtime-cache"></span>

Next: [tool resolution](https://github.com/manuscript-lang/manuscript/blob/main/crates/ms-clif/src/link/lld.rs), [build caches](builds/incremental-compilation.md) and [source-build setup](../contributing/rust-toolchain.md#build-and-run).
