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

Use `Debug` for source stepping, `Release` for distribution, and `RelWithDebInfo` for optimized code investigation or profiles.

## Levels and native settings

`build`, `run`, `test`, `debug`, and `profile` accept case-insensitive CMake-style names:

| Level | Optimization | Debugging information | Native flags |
| --- | --- | --- | --- |
| `Debug` | Disabled, including inlining | Retained uncompressed, with local source paths | `-gcflags=all=-N -l` `-ldflags=-compressdwarf=false` |
| `Release` | Go's normal optimizer | Symbol tables and DWARF stripped | `-trimpath -ldflags="-s -w"` |
| `RelWithDebInfo` | Go's normal optimizer | Retained, with local source paths | No additional flags |
| `MinSizeRel` | Go's normal optimizer | Symbol tables and DWARF stripped | `-trimpath -ldflags="-s -w"` |

Go has no `-Os` equivalent, so `MinSizeRel` currently matches `Release` and promises no smaller binary. Stack traces remain available. Build levels never change language semantics.

## Defaults and command behavior

- Default is `Release`; `debug` always uses `Debug`; `profile` defaults to `RelWithDebInfo`.
- `--debug` aliases `--build-type Debug` on `build`, `run`, and `test`.
- Conflicting debug selections, repeated build types, unknown levels, and build-type flags on source-only commands are rejected before compilation.
- Flags after `--` go to the program.
- Optimized debugging may skip or reorder source steps.
