# C implementation

All C code lives here. The earlier Rust implementation was deleted; its last commit is `660429d4`.

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
| `lsp/` | L5 | The language server behind `ms lsp`. |
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
fixtures, with each failure above the counts. The command fixtures must all pass; a difference in a corpus phase also fails
the target in the `ci` preset (`MS_CONFORM_ENFORCE=ON`; other presets report it). A PR that lowers a
count is not merged.

Fixtures are recorded from the `ms` built here: `ms run tools/conform-run.ms -- --record <fixture id>`. The Rust
`ms` they were first recorded from is in git history (`660429d4`) if a difference needs a second opinion.

## Command fixtures

Commands the corpus does not cover (`lint`, `inspect`, `init`, ...) have fixtures under
`tests/conformance/commands/<command>/<name>/`: `args`, optional `input/`, and `expected/`
(`stdout`, `stderr`, `status`, `tree/`). Record from the `ms` built here, review the diff, and replay with the
Manuscript runner:

```sh
MS=<ms> <ms> run tools/command-fixtures.ms -- record [--only-missing] [prefix]
MS=<ms> <ms> run tools/command-fixtures.ms -- check
```

`check` prints `commands: passed/total`.
