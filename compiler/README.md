# compiler

`libms`, the Manuscript compiler as a C library, replacing the Rust crates one stage at a time. Plan: [plan section 5, "Compiler"](../proposals/c-runtime.md) and the workstream list in the project files. This folder holds the front end so far: the lexer with the layout rules (`src/lex.c`), the syntax tree (`include/ms/ast.h`) and the parser (`src/parse.c`). Editor recovery (`partial.rs`), the formatter and diagnostic codes are not ported yet.

```
compiler/
  include/ms/   public headers: base.h (arena, names, diagnostics), token.h, lex.h, ast.h, parse.h, dump.h
  src/          one file per stage; libms.c includes them all, and building that one file builds the library
  tools/        ms_syntax_dump: prints tokens and trees for the comparison below
  tests/        syntax-diff.sh, mutate.c
```

## Rules

- No global state. Every function takes the arena or table it works in; a failed parse leaves nothing to free except the arena, which is dropped whole.
- Allocation failure aborts. Errors in the lexer and parser unwind with `longjmp` to the entry point.
- Static helpers in different files must not share names, because `libms.c` is one translation unit.
- Positions, messages, fixes and token boundaries equal the Rust front end's, byte for byte. The comparison below is the contract until the Rust front end is deleted.

## Checking against Rust

`make c-compiler-test` (`compiler/tests/syntax-diff.sh`) builds `crates/ms-syntax/examples/c_oracle.rs` and the C dump tool with AddressSanitizer and UBSan, runs both on every `.ms` file in the repository and on mutated copies (`MS_FUZZ`, default 3000; `MS_FUZZ_SEED`), and compares the outputs with `cmp`. A mutant is a corpus file with a few bytes inserted, deleted or swapped for lexer-hostile pieces, so most of them end in a lexer error and every message is compared. The nightly run uses more mutants.

`src/unicode_debug.inc` is the table of scalars that Rust's `{:?}` escapes, which error messages quote; `tests/gen_debug_table.rs` regenerates it.
