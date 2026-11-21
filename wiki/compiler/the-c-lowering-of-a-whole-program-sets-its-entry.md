# The C lowering of a whole program sets its entry

- `ms_lower_program` (`compiler/src/check/lower_func.c`) lowers the entry module first, then what it imports, then the standard modules. Each module is a view (`LbView`); a body is lowered with its own module's view entered.
- The entry is the lowered `main` of the entry module (`lb_entry_main`). A `main` that returns `Int` is exported and is the entry. Any other gets the wrapper `main.1` (`compiler/src/check/lower_entry.c`), written as the Rust lowering writes it: exit 0 after `Void`; for a `Result`, print `error: MESSAGE` on standard error and exit 1, else exit with the `Int?` payload or 0. A caller must not set `MirModule.entry` itself.
- `ms_lower_module` (one module, for `lower-diff.sh`) sets no entry.
- A `Void!` function that ends without a `return` returns `ok(void)` (`lb_return_void`). A function that ends without returning for any other result is reported as `falls off the end` in the why report, so no function disappears without a line.
- `lower-program-diff.sh` compares by file name, including the file of a `scope` line (the frame of a default argument). C numbers files by module order and Rust by first reference; the numbers are not worth matching.
- Several threads fixed the same hello-world gaps at once (defaults, generic `print`, std import cycles). Fetch `main` and read the last hour of merges before starting a checker or lowering gap.
