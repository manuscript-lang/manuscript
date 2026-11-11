[Wiki](../index.md) › [Testing and conformance](index.md)

# One test binary per crate; e2e stays per fixture

Verified (2026-11-06, 4-core Linux sandbox): every crate with two or more `tests/*.rs` files has one `tests/main.rs` (`[[test]] name = "it"`, `autotests = false`) that declares each file as a module. ms-syntax's 19 test binaries cost 38 s of CPU to build and link; the single binary costs 9 s. Shared helpers (`common`, `support`) are declared once in `main.rs`; files use `use crate::common;`. Test ids gain the module: `cargo nextest run -p ms-lsp --test it snapshots::`, `cargo test -p ms-syntax --test it -- comments::`, nextest filter `binary(=it) & test(=count_check::name)`.

Pitfalls: a test that re-executes its own binary with `--exact <name>` needs the module path in the name (`sort_guard::...`); a `mod x;` inside a module file would resolve below the module's directory, so helpers move to `main.rs`.

`ms test a.ms b.ms` builds many files into one executable, but it is slower for the e2e corpus: 309 clean fixtures (1579 tests, Release) take 385 s one fixture at a time on one core, 634 s as one binary on one core (LLVM cost grows faster than linearly with module size), and 98 s per fixture on four cores against 188 s as one binary. `tools/conform.ms` therefore keeps one `ms test` per fixture. Try fixed-size groups before changing it again.

Apply when: adding a Rust integration test file, or changing how e2e invokes `ms test`.
Evidence: [ms-syntax main.rs](../../crates/ms-syntax/tests/main.rs), [e2e runner](../../tools/conform.ms), [test_many_files](../../crates/ms-cli/tests/test_many_files.rs).
Verify: `cargo nextest run --workspace` lists the same tests under `<crate>::it`.
