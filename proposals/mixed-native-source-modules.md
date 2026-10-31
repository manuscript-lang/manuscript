# Mixed native and source stdlib modules

## Summary

- `stdlib/collections.ms` declares the native `List`/`Map`/`Set` methods; source methods on those types live in `stdlib/lists.ms` only because a module is either wholly native or wholly source.
- Change: `load()` in `crates/ms-check/src/stdlib.rs` splits a file that has both into a native half (the file's name) and a source half (a derived name), so every file-keyed map works unchanged.
- Then `lists.ms` is merged into `collections.ms`; no language, grammar, or user-visible change.
- Decision requested: none (internal). Implemented in this change.

## Status

Proposal, 2026-10-26, checked against 4e349ba. Direction: "Manuscript first", so more source methods on native types are expected; remove the split workaround.

## Problem

- `register` (`stdlib.rs:760`) makes any body (`has_implementation`) turn the whole module into a source module; `has_inherent_body` only picks the desugaring path (`load_module` vs `fold_inherent_impls`). A source module is checked as user source, so the bodyless native methods of `impl List[T]` are rejected, and a native module rejects any body (`native implementations must not have bodies`).
- Result: native `List` methods in `collections.ms`, source `sum`/`sorted`/`min`/`max`/`min_by`/`max_by` in `lists.ms`, which is also hard-coded in `EXTENSION_MODULES`.
- Cost: each new source method on a native type must be found in a different file than its siblings; the file name hides that `Map`/`Set` source methods would need yet another file.
- Non-goals: bounds on a source method's receiver (an inherent impl repeats the type's own parameters, so a bounded operation still uses an interface); changing wholly-source or wholly-native modules.
- Second stage: `bytecodecs.ms` has the same split from `bytes.ms` and merges the same way; its `extern def` readers go to the source half.

## Design

- A file is mixed when it has a bodied declaration and an inherent `impl` with a bodyless method. All other files load as today.
- Source half: contract `impl`s with bodies, bodied top-level `fn`/`const`/`test`, records/alternatives with bodied methods, and each `interface` whose impls are all bodied. Native half: everything else.
- A bodied inherent `impl Receiver[T]:` in a mixed file is rewritten in the source half to a generated unexported interface `ReceiverSourceMethods[T]` (signatures copied with fresh node ids) plus `impl ReceiverSourceMethods[T] for Receiver[T]`, so a source method needs no interface written by hand. A default argument on such a method is an error (bounded or defaulted operations use an explicit interface). The receiver must repeat its type's parameters, as for native inherent impls.
- The source half imports its own file (`from "@std/bytes.ms" import Bytes`) to name the native half's types; the native half drops that import.
- The source half is a separate `Module` named `<file>+source` (`@std/collections.ms+source`); the native half keeps `@std/collections.ms`. Each half takes its own desugaring path. Maps keyed by file (`modules`, `source_modules`, `done`, `checking`, `id_scope`, `source_reach`) need no change: the halves never share a key. A review of the first draft (same name for both halves) found `native_sources`, `standard_exports`, `import_symbols`, and `hints.rs` would conflate them.
- The source half is an extension module (`EXTENSION_MODULES` lists `@std/collections.ms+source`). It sees native `List`/`Map` through the prelude, as `lists.ms` does now.
- Diagnostics and positions of the source half use the original line/column, so the half is rendered under `collections.ms`; `standard_modules()` lists the file once and `ms-lsp` maps `+source` back to it.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `crates/ms-check/src/stdlib.rs` | partition in `load`, identity-based `native_sources`, `EXTENSION_MODULES` | `crates/ms-check/tests/list_methods.rs`, new mixed-file load test |
| `stdlib/collections.ms`, `stdlib/lists.ms` | merge | existing stdlib/conformance tests |
| `crates/ms-lsp` snapshots | `lists.ms` navigation target becomes `collections.ms` | `navigation.jsonl` |
| `wiki/stdlib-design/index.md`, docs mentioning `lists.ms` | update | `make repo-check` |
| parser, grammar, lowering, codegen, runtime | unchanged | |

## Alternatives

- Do nothing (plus a pointer comment): works today and the split is 157 lines of per-numeric `sum` impls; the cost is a parallel file per native type and a hidden rule. It loses only if more source methods on native types are expected, which is the stated direction.
- Make `register` per-declaration instead of per-module: the same effect without splitting the AST, but `native_sources`, `scope_module`, and the checker's `bundled` mode all assume one module per file, so it touches more.
- Allow bodies in native inherent impls: needs the lowering of native vs source dispatch per method; larger and changes ABI-visible behavior.

## Staging and verification

- One PR: loader change plus merge, since the merge is the test. `cargo nextest run --workspace`, clippy, fmt, `make conform`, `make repo-check`.
- Go/no-go: if splitting needs checker changes beyond `stdlib.rs`, stop and report.

## Open questions

None.
