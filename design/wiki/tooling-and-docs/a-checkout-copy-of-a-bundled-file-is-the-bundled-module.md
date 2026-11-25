[Wiki](../index.md) › [Tooling and docs](index.md)

# A checkout copy of a bundled file is the bundled module

Failure: an editor opened `src/stdlib/math/math.ms` and showed `expected Result[BigInt, Error], found Result[BigInt, Error]` (MS3001) across the standard library. The file was loaded as a user module while `@std/math/math.ms` was loaded again from the bundle, so every type was declared twice. The two print alike and never compare equal.

Decision: the project loader marks a file at `<repo>/src/stdlib/<name>` (`core/<name>` for the prelude), found by `src/layers.txt` beside it, as the bundled module `<name>`. The checker gives it that identity (`MsModuleInfo.id`) while still reporting under its file name, and applies the standard library's rules to it, not a program's. Use `ms_check_is_user_module`, not `module < user_modules`, to gate a rule on user code. The language server names a `manuscript-stdlib:` document the same way (`MsLoadOptions.entry_std_name`). What the editor indexes (type references, occurrences) follows `module < user_modules`, not `ms_check_is_user_module`: a bundled copy is checked as library code but must still be navigable. A mismatch between two same-named types now says where each is declared.

Apply when: adding a check that differs for user and bundled code, or changing how a module is identified.
Evidence: [imports](../../../src/compiler/check/imports.c), [loader](../../../src/compiler/project/load.c), `std_checkout` in `cmake/targets/cli.cmake`, conformance fixture `e2e/projects/same_name_types`.
Verify: `ms check src/stdlib/<any>.ms` reports nothing, and `tests/lsp/stdlib_bodies` jumps and hovers inside `bytes`, `collections` and `core`.
