+++
title = "Build levels"
weight = 2
+++

# Build levels

`--build-type` sets native optimization and debugging information. The default is an optimized Release executable.

Save this entrypoint as `main.ms`:

```manuscript
export fn main() Int:
    return 0
```

Choose a level when building or running it:

```sh
ms build main.ms --build-type Release -o program
ms build main.ms --build-type MinSizeRel -o small-program
ms run main.ms --build-type Debug
```

Use `Debug` for unoptimized code and source attribution, `Release` for optimized code and profiles, and `MinSizeRel` for the smallest executable.

## Levels

`build`, `run`, `test`, and `profile` accept case-insensitive CMake-style names:

| Level | Optimization | Symbol table |
| --- | --- | --- |
| `Debug` | Disabled, including inlining | Kept |
| `Release` | Speed | Kept, so profilers and backtraces show names |
| `MinSizeRel` | Speed and size | Stripped |

Every level links with `--gc-sections` (`-dead_strip` on macOS), so runtime and standard-library code the program never reaches is dropped. On Linux x86_64 an empty program is about 0.45 MB and an HTTP server about 4.4 MB (before this, 1.8 MB and 7.7 MB). Build levels never change language semantics.

## Defaults and command behavior

- The default is `Release`, including for `profile`.
- Repeated build types, unknown levels, and build-type flags on source-only commands are rejected before compilation.
- Flags after `--` go to the program.
- Optimized code may reorder or remove source operations. DWARF provides file/line lookup, without variable, type, or inline-frame information; see [native debugging](../debugging/debugger-integration.md).
