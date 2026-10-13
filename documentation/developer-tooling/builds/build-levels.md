+++
title = "Build levels"
weight = 2
+++

# Build levels

Build levels control native optimization and debugging information. The default is an optimized Release executable.

Save this entrypoint as `main.ms`:

```manuscript
export fn main() -> Int:
    return 0
```

Choose a level when building or running it:

```sh
ms build main.ms --build-type Release -o program
ms build main.ms --build-type MinSizeRel -o small-program
ms run main.ms --build-type Debug
```

Use `Debug` for source stepping, `Release` for distribution, and
`RelWithDebInfo` when investigating optimized code or capturing profiles.

## Levels and native settings

`--build-type` accepts case-insensitive CMake-style names on `build`, `run`,
`test`, `debug`, and `profile`:

| Level | Optimization | Debugging information | Native flags |
| --- | --- | --- | --- |
| `Debug` | Disabled, including inlining | Retained uncompressed, with local source paths | `-gcflags=all=-N -l` `-ldflags=-compressdwarf=false` |
| `Release` | Go's normal optimizer | Symbol tables and DWARF stripped | `-trimpath -ldflags="-s -w"` |
| `RelWithDebInfo` | Go's normal optimizer | Retained, with local source paths | No additional flags |
| `MinSizeRel` | Go's normal optimizer | Symbol tables and DWARF stripped | `-trimpath -ldflags="-s -w"` |

Go has no equivalent to C++'s `-Os` or `-Oz`. `MinSizeRel` currently uses the
same native settings as `Release`; it does not promise a smaller binary than
`Release`. Both omit debugging data to reduce binary size. Runtime stack traces
remain available. Optimization does not change Manuscript language semantics.

## Defaults and command behavior

The default is `Release`, except `debug` always uses `Debug` and `profile`
defaults to `RelWithDebInfo`. Optimized debugging may skip or reorder source
steps. `--debug` remains an alias for `--build-type Debug` on `build`, `run`, and
`test`. Conflicting debug selections, repeated build types, unknown levels,
and build-type flags on source-only commands are rejected before compilation.
Flags after `--` are passed to the program.

Project commands create `ms.lock` when it is missing and otherwise require the
matching pins. Run `ms lock ms.toml` to explicitly update its compiler and toolchain pins.
Select build levels on the command line. See [build pinning and cache identity](reproducibility.md).

## Compiler API

The compiler API offers `BuildWithType` and `BuildCheckedWithType` for explicit
selection. `Build` defaults to Release; the existing `BuildChecked` boolean
selects Debug when true and Release otherwise. Build levels share `ms.lock`
toolchain pins but have distinct artifact cache identities.
