# compiler

`libms`, the Manuscript compiler as a C library, replacing the Rust crates one stage at a time. Plan: [plan section 5, "Compiler"](../proposals/c-runtime.md) and the workstream list in the project files. This folder holds the front end so far: the lexer with the layout rules (`src/lex.c`), the syntax tree (`include/ms/ast.h`) and the parser (`src/parse.c`). Diagnostic codes are in `src/diag.c` and editor recovery in `src/partial.c`. The formatter is written in Manuscript over this library.

```
compiler/
  include/ms/   public headers: libms.h (entry points and the stage table), driver.h, base.h (arena, names, diagnostics), token.h, lex.h, ast.h, parse.h, dump.h, diag.h
  src/          one file per stage; libms.c includes them all, and building that one file builds the library
  tools/        ms (the thin executable over the driver), ms_syntax_dump: prints tokens and trees for the comparison below
  tests/        syntax-diff.sh, mutate.c, driver-test.sh
```

## Rules

- No global state. Every function takes the arena or table it works in; a failed parse leaves nothing to free except the arena, which is dropped whole.
- Allocation failure aborts. Errors in the lexer and parser unwind with `longjmp` to the entry point.
- Static helpers in different files must not share names, because `libms.c` is one translation unit.
- Positions, messages, fixes and token boundaries equal the Rust front end's, byte for byte. The comparison below is the contract until the Rust front end is deleted.

## Checking against Rust

`make c-compiler-test` (`compiler/tests/syntax-diff.sh`) builds `crates/ms-syntax/examples/c_oracle.rs` and the C dump tool with AddressSanitizer and UBSan, runs both on every `.ms` file in the repository and on mutated copies (`MS_FUZZ`, default 3000; `MS_FUZZ_SEED`), and compares the outputs with `cmp`. A mutant is a corpus file with a few bytes inserted, deleted or swapped for lexer-hostile pieces, so most of them end in a lexer error and every message is compared. The nightly run uses more mutants.

`src/unicode_debug.inc` is the table of scalars that Rust's `{:?}` escapes, which error messages quote; `tests/gen_debug_table.rs` regenerates it.

## Driver and stages

`libms.h` has one entry point and one row in the stage table (`ms_stage_impl`) per pipeline stage: parse, format, check, lower, emit, link, and the command's own tool logic. `driver.c` knows which stages each command needs. A command runs in C only when every stage it needs is in C; otherwise the whole command goes to the Rust `ms` (`$MS_RUST_CLI`, or `ms-rust` beside the executable), so the conformance corpus runs through the C `ms` from the first day and a command flips to C when its last stage lands. Stage data cannot cross between the two implementations, which is why the handover is per command. `MS_DRIVER_TRACE=1` prints the choice; `MS_STAGES=parse=rust` overrides a row for comparison runs. Porting a stage: add its entry point to `libms.h`, write it in `src/`, flip its row. `make c-driver-test` runs the unit tests and checks that `ms` in front of the Rust `ms` gives identical output and status.
