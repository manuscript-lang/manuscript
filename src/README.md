# C implementation

All C code lives here; Rust stays in `crates/` (frozen at `660429d4`). The plan is
`c-implementation/restart-plan-consolidated-2026-11-21.md`.

## Build

```sh
cmake --preset debug
cmake --build --preset debug
ctest --preset debug
```

Presets: `debug` (-O0), `ci` (-O2 with frame pointers; CI builds and replays the corpus with it, about 4x faster per `ms` process than `debug`), `release`, `sanitize`. Ninja on every platform; clang is the compiler.

Build output goes to `.artifacts/build/<preset>`. Generated files never go into `src/`.

## Layers (an include crosses layers only downward)

| Directory | Layer | Role |
| --- | --- | --- |
| `base/` | L1 | Safe wrappers, values, arena, status, file, path, json. libc only. |
| `abi/` | L1 | Layouts, symbol names, fault kinds. Read by compiler and runtime. |
| `runtime/` | L1 | `sys`, `core`, `io`, `net`, `std`. |
| `compiler/` | L2 to L4 | `syntax project check own lower mir opt emit link`. Depends on `base` and `abi` only. |
| `cli/` | L5 | The thin `ms` entry point. |
| `lint/` | L0 | `ms_lint`. |
| `third_party/` | L1 | Vendored libraries and `c-libs.lock`. |

`OWNERS` names the owner of each layer. Nobody edits another layer.

## Adding a module

1. Put it in the layer directory and add it to that layer's file in `cmake/targets/` (all build rules live there; `src/` holds only sources).
2. Use `ms_target_defaults(<target>)`: strict warnings are errors, no exemptions.
3. Start the file with a comment saying what it owns. Check `base` first for any helper.

`ms` runs every phase and names each one not yet implemented (exit status 70).

## Conformance

```sh
cmake --build --preset ci --target conform
```

replays the corpus with the ms built here (`tools/conform-run.ms`, a Manuscript program that ms runs) and prints
`phase: passed/total` for `parse`, `check`, `run` and `test`, then `commands: passed/total` for the command
fixtures, with each failure above the counts. The command fixtures must all pass; the corpus phases are reported
until the port is complete (`-DMS_CONFORM_ENFORCE=ON` fails the target on any difference). A PR that lowers a
count is not merged.

The frozen Rust `ms` from `660429d4` is only the oracle fixtures were recorded from: build it with the `Oracle`
workflow when a fixture needs re-recording.

## Command fixtures

Commands the corpus does not cover (`lint`, `inspect`, `init`, ...) have fixtures under
`tests/conformance/commands/<command>/<name>/`: `args`, optional `input/`, and `expected/`
(`stdout`, `stderr`, `status`, `tree/`). Record from the oracle and replay with the Manuscript
runner, one PR per command:

```sh
MS=<oracle ms> <oracle ms> run tools/command-fixtures.ms -- record [--only-missing] [prefix]
MS=<ms under test> <oracle ms> run tools/command-fixtures.ms -- check
```

`check` prints `commands: passed/total`.
