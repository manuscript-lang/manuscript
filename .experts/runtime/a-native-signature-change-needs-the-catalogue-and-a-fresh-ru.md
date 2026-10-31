[Wiki](../index.md) › [Runtime](index.md)

# A native signature change needs the catalogue and a fresh runtime archive

Verified: lowering marshals native calls from `crates/ms-rt/SYMBOLS.md`, not from the Rust source, and programs link `target/ms-native/libms_native.a`. Adding parameters to `msstd_process_command_spawn` without editing its catalogue line made compiled calls pass the out pointer as a mode and segfault inside the native; a stale archive instead ignored the new arguments. Crate tests that call the native directly passed both times. A payload-free alternative parameter crosses as its case index (`p.ty == "i64"`), and a bundled declaration's default such as `Stdio.Pipe` is built by `literal_default`.

Apply when: changing the parameters of any `ms-std-*` or `ms-rt` export.
Evidence: [catalogue](../../crates/ms-rt/SYMBOLS.md), [Stdio default](../../crates/ms-lower/src/call.rs), [called source check](../../tests/e2e/testdata/stdlib/host.ms).
Verify: run `make runtime` and rebuild `ms-cli`, then run a compiled program that calls the native, not only crate tests; `runtime_symbol_catalogue_matches_archive` checks names, not parameters.
