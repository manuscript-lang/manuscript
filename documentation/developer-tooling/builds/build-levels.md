+++
title = "Build levels"
weight = 2
+++

# Build levels

`--build-type` sets native optimization and debugging information. `ms build` and `ms bench` default to an optimized Release executable. `ms run` and `ms test` default to Debug, which compiles with Cranelift and builds much faster; pass `--build-type Release` to run or test the optimized (LLVM) code.

Save this entrypoint as `main.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"ready\n"} -->
```manuscript
fn main() Unit:
    print("ready")
```

Choose a level when building or running it:

```sh
ms build main.ms --build-type Release -o program
ms build main.ms --build-type MinSizeRel -o small-program
ms run main.ms --build-type Debug
```

The two builds report `Built program` and `Built small-program`. The debug run prints `ready`.

Use `Debug` for unoptimized code and source attribution, `Release` for optimized code and profiles, and `MinSizeRel` for the smallest executable.

On Linux, the default executable runs on glibc 2.28 or newer. Use `--static` with `build`, `run`, `test`, or `bench` to produce a self-contained musl executable for deployment without a glibc dependency. See [platform linking](https://github.com/manuscript-lang/manuscript/blob/main/documentation/contributing/rust-toolchain.md#platform-linking) for target details.

## Levels

`build`, `run`, `test`, and `profile` accept case-insensitive CMake-style names:

| Level | Optimization | Symbol table |
| --- | --- | --- |
| `Debug` | Disabled, including inlining | Kept |
| `Release` | Speed | Kept, so profilers and backtraces show names |
| `MinSizeRel` | Speed and size | Stripped |

Every level links with `--gc-sections` (`-dead_strip` on macOS), so runtime and standard-library code the program never reaches is dropped. Executable size depends on the target, build level and reachable library code. Build levels never change language semantics.

## Defaults and command behavior

- The default is `Release` for `build`, `bench` and `profile`, and `Debug` for `run` and `test`.
- Repeated build types, unknown levels, and build-type flags on source-only commands are rejected before compilation.
- Flags after `--` go to the program.
- Optimized code may reorder or remove source operations. DWARF provides file/line lookup, without variable, type, or inline-frame information; see [native debugging](../debugging/debugger-integration.md).
