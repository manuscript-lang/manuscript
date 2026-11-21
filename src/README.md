# C implementation

All C code lives here; Rust stays in `crates/` (frozen at `660429d4`). The plan is
`c-implementation/restart-plan-consolidated-2026-11-21.md`.

## Build

```sh
cmake --preset debug
cmake --build --preset debug
ctest --preset debug
```

Presets: `debug`, `release`, `sanitize`. Ninja on every platform; clang is the compiler.
Build output goes to `.artifacts/build/<preset>`. Generated files never go into `src/`.

## Layers (an include crosses layers only downward)

| Directory | Layer | Role |
| --- | --- | --- |
| `base/` | L1 | Safe wrappers, values, arena, status, file, path, json. libc only. |
| `abi/` | L1 | Layouts, symbol names, fault kinds. Read by compiler and runtime. |
| `runtime/` | L1 | `sys`, `core`, `io`, `net`, `std`. |
| `compiler/` | L2 to L4 | `syntax project check own lower mir opt emit link`. Depends on `base` and `abi` only. |
| `driver/` | L5 | The thin `ms` entry point. |
| `ms/` | L5 | The Manuscript front: `*.ms` files. |
| `lint/` | L0 | `ms_lint`. |
| `third_party/` | L1 | Vendored libraries and `c-libs.lock`. |

`OWNERS` names the owner of each layer. Nobody edits another layer.

## Adding a module

1. Put it in the layer directory and add it to that directory's `CMakeLists.txt`.
2. Use `ms_target_defaults(<target>)`: strict warnings are errors, no exemptions.
3. Start the file with a comment saying what it owns. Check `base` first for any helper.

`ms-c` runs every phase and names each one not yet implemented (exit status 70).

## Oracle and the gate

The frozen Rust `ms` and `ms-conform` from `660429d4` are the oracle. Build them from that
commit (`make build`, `cargo build --release --locked -p ms-conform`), keep them outside the
repository, and point `MS_ORACLE_DIR` at the directory holding both.

```sh
MS_ORACLE_DIR=<dir> cmake --build --preset debug --target conform-c
```

prints `phase: passed/total` for `parse`, `check`, `run` and `test`. Select a subset with
`-DMS_CONFORM_EXTRA="--tag;tier-core"`. A PR that lowers any phase count is not merged.

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
