# Index the checker's type and method tables

## Summary

- Problem: `ms check` spends 40% of its instructions in `Checker::implements`, a linear scan of every method per query, and 35% of the profile in hashing and malloc. Types are `Rc<Type>` trees compared and hashed structurally by `Name`.
- Change: stage 1 (done) indexed methods by contract. Stages 2 and 3 intern checker types as dense `TyId`s and replace the rendered-text keys with them; stage 4 replaces the name-dispatched structural properties with a dense table of property bits.
- Decision requested: none (no language change). Output of `ms check`, `ms emit` and the conformance corpus stays byte-identical.

## Status

Stage 1 implemented, 2026-11-02 (`c30abc7d`). Stages 2 to 4 proposed 2026-11-03 against `e222a770`, from compiler-hacks audit items 7, 25 and 27. Direction (Chinmay): "caching is cope for a slow design. do not add caches and delete all existing caches". The earlier skeptic review scoped stage 2 out for lack of evidence; the audit now supplies it (below).

## Problem

Stage 1 removed the `implements` scan. What remains is text standing in for type identity:

- Lowering renders a type to a `String` (`lowering_key`, `types.rs:1262`) for `Cx::tycache: HashMap<String, MTy>` (`cx.rs:199`) and for every generic instance key (`InstKey.subst: Vec<(Name, String)>`, `cx.rs:29`, built in `func.rs:173`). Receiver matches in `json.rs`, `mathops.rs`, `fixture.rs`, `iface.rs` compare rendered `type_key` text (13 sites in `ms-lower`).
- The checker memoizes `Equal`, `Hashable` and `Clonable` in `HashMap<(String, Property), bool>` keyed by `type_key(t)` (`contracts.rs:1061`), with `active.len() > 200` as a recursion guard, and special-cases the five properties by contract name (`implements`, `contracts.rs:753`; `builtin_comparable`, a list of primitive names). `PropertyState` is the cache the owner asked to remove.
- `Type` is a mutable `Rc` tree (`bounds`, `default` in `RefCell`; `Definition` fields in `RefCell`), so no integer identity exists. Rendering a key allocates and walks the whole tree on every `lower_ty`.
- Measured (`ms emit`, lowering-table thread): `tycache` is 0.07% of emit, so this is a design cleanup with a speed bonus, not a speed fix. `PropertyState` cost is measured in stage 4 before it merges.

## Design

`TyId(u32)` indexes `TyTable` (`ms-check/src/tytable.rs`), a struct of arrays of type constructors, append-only and owned by `Cx` (lowering substitutes new types, so ids are handed out on demand, never frozen):

- Columns: `ids: Vec<Name>`, `kinds: Vec<Kind>`, `starts`, `nparams`, `nargs`, and `pool: Vec<u32>` holding each row's function parameters (child `TyId` plus `var` and lifted flag bits), the function result, then type arguments.
- Dedup is one open-addressed slot table over `(id, kind, params, result, args)` with children already `TyId`s: a lookup hashes integers and never renders text. A representative `Ty` per row serves callers that still need fields; identity never reads it (bounds, `defaults`, `builtin`, `def` are not part of identity, as in `write_type_key`).
- Two identities, matching the two renderers: `intern` equals `lowering_key` equality (lifted parameters distinguish), `shape` equals `type_key` equality. A differential unit test checks both, and `same`, over generated types.
- Types are interned after `required_type`, as `lowering_key` is today. Instance keys sort by variable name (unique in a substitution), not by id, so output does not depend on interning order.

Stage 2 (lowering, this PR): `Cx` owns the `TyTable`. `tycache` becomes `Vec<Option<MTy>>` indexed by `TyId` (it is then a dense side column, not a text-keyed cache). `InstKey.subst` holds `(Name, TyId)`. The 13 `type_key` receiver comparisons become `TyId` equality. `$own` and `$evidence` stay for now (audit item 7, separate S change).

Stage 3 (checker, done): the checker builds `TyId`s from `unify`/`same` results where it keys types (`reported`, `seen`, `recursion.rs` ancestors, `stmts.rs:1119`), removing the other `type_key` users. Open hazard: `sub` clones variables to snapshot bounds, so a variable's identity is its `id`, not the clone; keys include `id` as today. Whether `RefCell`s can go after a one-pass declaration phase (audit item 27) is decided after this stage, not promised.

Stage 4 (properties), split by what is sound:
- Done in stage 3: `Property::of` and the property bound checks use the `Builtin` tag, not contract-name text.
- Not possible as the audit wrote it: `Comparable` for primitives cannot come from `impl Comparable for Int` declarations because none exist in `stdlib/` (the audit was wrong), and `builtin_comparable` also drives `scalar_extension` (`contracts.rs:380`). Adding them is a stdlib and lowering change of its own.
- Not done: dense property bits with no memo. They are not a function of the nominal type alone: visible impls differ per module (`method_visible`), generic instances depend on `bounds_satisfied`, `Data` depends on the ancestor, `Equal` and `Hashable` take opposite cycle assumptions, and the 200-deep guard returns false. The memo (`completed`) also keeps shared-DAG types from going exponential (`type_graph_tests`). A replacement needs bits keyed by (`TyId`, visibility scope) filled in a bottom-up pass, validated side by side with `property_in` over the corpus. That is a separate proposal and PR.

Invariants: diagnostics, emitted MIR and generated names are byte-identical; no cache, no new crate, no test gated.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `ms-check/src/tytable.rs` (new), `types.rs` | `TyTable`, `intern` | unit tests: equal trees share an id, lifted flag and `var` flag distinguish, args order matters |
| `ms-lower/src/cx.rs`, `func.rs`, `json.rs`, `mathops.rs`, `fixture.rs`, `iface.rs` | `TyId` keys | `cargo nextest run --workspace`, conformance diff |
| `ms-check/src/contracts.rs`, `recursion.rs`, `stmts.rs`, `checker.rs` | stage 3 | `ms-check` tests, `generic_recursion`, conformance diff |

## Alternatives

- Do nothing: text keys stay; the audit's items 7, 25 and 27 stay open.
- Intern during checking by storing the id in `Type`: needs every `Type` construction (`Type::new`, struct literals, `sub`, `required_walk`) to allocate an id while bounds and definitions are still being filled; rejected for this change, revisited after stage 3.
- Memoize properties by `TyId`: still a cache (owner rule); stage 4 needs its own design.

## Stages

1. Done. 2. `TyTable` and lowering keys. 3. Checker keys. 4. Property bits (separate proposal). Each stage is one PR with auto-merge and full CI green; stage 3 also reports `ms check` Ir on the 122k-line workload. The helper and vtable string keys that embed a type id (`json-tree:`, `impl:`, `close_parts:`) stay strings until a helper-key enum lands.
