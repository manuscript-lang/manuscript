# compiler

`libms`, the Manuscript compiler as a C library, replacing the Rust crates one stage at a time. Plan: [plan section 5, "Compiler"](../proposals/c-runtime.md) and the workstream list in the project files. This folder holds the front end (the lexer with the layout rules `src/lex.c`, the syntax tree `include/ms/ast.h`, the parser `src/parse.c`) and the start of the checker: the tables every pass reads (`types.c`, `tables.c`) and the standard-library loader (`stdlib.c`). Editor recovery (`partial.rs`), the formatter and diagnostic codes are not ported yet.

```
compiler/
  include/ms/   public headers: libms.h (entry points and the stage table), driver.h, base.h (arena, names, diagnostics), token.h, lex.h, ast.h, parse.h, types.h, tables.h, stdlib.h, dump.h
  src/          one file per stage; libms.c includes them all, and building that one file builds the library
  tools/        ms (the thin executable over the driver), ms_syntax_dump: prints tokens and trees for the comparison below
  tests/        syntax-diff.sh, mutate.c, driver-test.sh, check-diff.sh, types_test.c
```

## Rules

- No global state. Every function takes the arena or table it works in; a failed parse leaves nothing to free except the arena, which is dropped whole.
- Allocation failure aborts. Errors in the lexer and parser unwind with `longjmp` to the entry point.
- Static helpers in different files must not share names, because `libms.c` is one translation unit.
- Positions, messages, fixes and token boundaries equal the Rust front end's, byte for byte. The comparison below is the contract until the Rust front end is deleted.

## Checking against Rust

`make c-compiler-test` (`compiler/tests/syntax-diff.sh`) builds `crates/ms-syntax/examples/c_oracle.rs` and the C dump tool with AddressSanitizer and UBSan, runs both on every `.ms` file in the repository and on mutated copies (`MS_FUZZ`, default 3000; `MS_FUZZ_SEED`), and compares the outputs with `cmp`. A mutant is a corpus file with a few bytes inserted, deleted or swapped for lexer-hostile pieces, so most of them end in a lexer error and every message is compared. The nightly run uses more mutants.

`src/unicode_debug.inc` is the table of scalars that Rust's `{:?}` escapes, which error messages quote; `tests/gen_debug_table.rs` regenerates it.

## The checker tables

`MsTyTable` (`types.h`) is the one representation of checked types: a struct of arrays of interned type constructors, indexed by `MsTy`. Equal types share an index, so identity is an integer compare; type variables are never shared. `MsCheck` (`tables.h`) holds the type table, the symbol columns (name, identity text, kind, module, native binding, export flag, declaration, type, variable count) and one row per module with its scope. A pass adds columns beside these, indexed by the same ids. `ms_std_load` (`stdlib.h`) parses the bundled files, splits a file that mixes native operations with bodies into a native half and a `+source` half, and registers symbols as the Rust loader does. `compiler/tests/check-diff.sh` compares the result with `crates/ms-check/examples/c_oracle.rs` byte for byte. Later passes (resolution, types, interfaces, ownership, effects) add their own lines to that script.

## Driver and stages

`libms.h` has one entry point and one row in the stage table (`ms_stage_impl`) per pipeline stage: parse, format, check, lower, emit, link, and the command's own tool logic. `driver.c` knows which stages each command needs. A command runs in C only when every stage it needs is in C; otherwise the whole command goes to the Rust `ms` (`$MS_RUST_CLI`, or `ms-rust` beside the executable), so the conformance corpus runs through the C `ms` from the first day and a command flips to C when its last stage lands. Stage data cannot cross between the two implementations, which is why the handover is per command. `MS_DRIVER_TRACE=1` prints the choice; `MS_STAGES=parse=rust` overrides a row for comparison runs. Porting a stage: add its entry point to `libms.h`, write it in `src/`, flip its row. `make c-driver-test` runs the unit tests and checks that `ms` in front of the Rust `ms` gives identical output and status.

## Effects

`effects.h` holds the two parts of the effect pass that need only source text and a reference graph: `effect_directives.c` reads `// ms: effect` and `// ms: allow_effect` lines and matches patterns, and `effect_reach.c` propagates declared effects through the graph and reports project callables that reach an effect no scope permits. `check-diff.sh` compares both with the Rust code (`c_oracle_effects.rs`) on every `.ms` file and on generated graphs (`effect_graph_gen.c`). Building the graph from checked code (the scan) comes when the typed-tree columns of `facts.h` exist.
