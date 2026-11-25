[Wiki](../index.md) › [Tooling and docs](index.md)

# A checkout copy of a bundled file is the bundled module

Failure: an editor opened `src/stdlib/math/math.ms` and showed `expected Result[BigInt, Error], found Result[BigInt, Error]` (MS3001) across the standard library. The file was loaded as a user module while `@std/math/math.ms` was loaded again from the bundle, so every type was declared twice. The two print alike and never compare equal.

Decision: the project loader marks a file at `<repo>/src/stdlib/<name>` (`core/<name>` for the prelude), found by `src/layers.txt` beside it, as the bundled module `<name>`. The checker gives it that identity (`MsModuleInfo.id`) while still reporting under its file name, and applies the standard library's rules to it, not a program's. Use `ms_check_is_user_module`, not `module < user_modules`, to gate a rule on user code. The language server names a `manuscript-stdlib:` document the same way (`MsLoadOptions.entry_std_name`). What the editor indexes (type references, occurrences) follows `module < user_modules`, not `ms_check_is_user_module`: a bundled copy is checked as library code but must still be navigable. A mismatch between two same-named types now says where each is declared.

Apply when: adding a check that differs for user and bundled code, or changing how a module is identified.
Evidence: [imports](../../../src/compiler/check/imports.c), [loader](../../../src/compiler/project/load.c), `std_checkout` in `cmake/targets/cli.cmake`, conformance fixture `e2e/projects/same_name_types`.
Verify: `ms check src/stdlib/<any>.ms` reports nothing, and `tests/lsp/stdlib_bodies` jumps and hovers inside `bytes`, `collections` and `core`.

## Language-server regression nets

- `ctest -R lsp_sweep` (`tools/lsp-sweep.ms`) asks `ms lsp` for the definition and hover of every identifier in every stdlib module (`-- bytes.ms` limits it): a jump onto text that is not the identifier, or hover missing above the ceiling, fails it. Add a module to it when a construct stops navigating.
- The supervisor's queue must never make the worker's reader wait behind client frames: a client that pipelines thousands of requests deadlocked the supervisor and worker on each other's pipes. Only client frames wait for room.
- Navigation gaps found by the full sweep: a field read on a value narrowed by `!= null` (the facts keep `T?`), enum case payload fields (declaration, `Kind.Case(label: x)`), `{field: name}` destructuring labels, a generic function written `f[Int](...)` (the index used to leave the name out), a `match` over an optional, labels of an extern call, and type-set names (`type Ordered = Int | String`) as receivers and bounds. Rebuild `ms` before sweeping: the server reads the stdlib embedded in the binary, not the checkout.

- The analysis cache holds 8 entries and evicts the least recently used, freeing its arena. Code that holds an analysis (rename's `changed` edits live in its arena) and then analyzes other files must use `lsp_analyze_scan`, which reuses a hit but never inserts; `lsp_analyze` there freed the held analysis once a project had more than 8 files (crash, then a rename refused over garbage). `tests/lsp/many_files` replays references, rename and workspace symbols over 11 files.
- A failed import of a missing local file (`MsGraphModule.missing`) reports once; names imported from it are not reported again as unknown. Imports of unknown std modules keep their cascade, which the conformance goldens record for the CLI.
- `workspace/symbol` analyzes every file whose text mentions the query, so short queries over a big folder are slow and block the single-threaded server.
