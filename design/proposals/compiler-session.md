# Compiler session

## Summary

- The checker keeps the standard library in a `thread_local!` (`stdlib.rs:81`) and numbers bindings from a process atomic (`checker.rs:16`); the interner is a leaking process table (`symbol.rs:16`).
- Introduce `ms_check::Session`: it owns the standard-library world and the binding counter, `Program` carries it, and every consumer reads the world through it.
- Decision requested: none (no language or user-visible change). The interner is scoped out below with evidence.

## Status

Implemented 2026-11-03 (stages 1 and 2 in one PR); checked against `e222a770`. Review: an independent skeptic confirmed the facts and found `PRIMS` understated; folded in below. Audit items 6 and 12 in `compiler-hacks-audit-2026-11-03.md`.

## Problem

- Verified: `ensure_standard` has a three-state loader (`state` 0/1/2) and 25 call sites (11 in `stdlib.rs`). Any caller on a different thread sees an unloaded world; `is_prelude_symbol` compares `Rc` pointers against that thread's world.
- Verified: `BINDING_SERIAL` is shared by the standard-library checker and the program checker only because both run on one process. The comment says so.
- Audit item 6 also cites a thread-local `NodeId` counter at `0x8000_0000`; it no longer exists (no match in `crates/`, only a stale line in `ms-check/HIR.md`). Item 12 says `Symbol` hashes by pointer; it already hashes by intern order (`symbol.rs:14,50`). Both parts are stale.

## Design

- `Session { world: RefCell<World>, bindings: Cell<usize> }`. `World` is the existing struct, unchanged. `Session::new()` loads lazily as `ensure_standard` does now; the loader state stays inside it.
- The `pub fn` queries in `stdlib.rs` that touch the world (`standard_symbol`, `is_prelude_symbol`, `ensure_source`, `done`, `operation_variables`, ...) become `Session` methods. Pure helpers (`module_stem`, `owns_value`, `PRIMITIVE_NAMES`) stay free functions.
- `Checker` holds `Rc<Session>`; nested standard-module checkers get the same `Rc`, which is what the global atomic stood in for. `Binding::uid` comes from `session.bindings`.
- `Program` holds `session: Rc<Session>`. `ms-lower`, `ms-lsp`, `ms-tooling` and `editor.rs` use `program.session` or a `Session` they own (the LSP and `ms guide` hold one for their lifetime).
- API: `check_in(&Session, modules, imports, options)`. `check(...)` stays as `check_in(&Session::new(), ...)`, so the 30 existing callers and tests do not change. A session is not `Send`; one per thread is the rule, now enforced by the type instead of by luck.
- No cache is added. The loaded world is the session's data, not memoized results; `check` on a fresh session does the same work a fresh thread does today.
- `PRIMS` (`types.rs:694`) is thread-local `Rc` identity that type comparison relies on (`types.rs:885`, `hints.rs:427`), so a session stays valid only on the thread that built it. That is a stated constraint here, not removed; it moves with the type table in audit item 7. Parallel checking is therefore not a benefit of this change.

## Interner (scoped out)

- A session-owned `Symbol(u32)` cannot keep `Deref<Target = str>` and `as_str() -> &'static str` without either an unsafe lifetime cast tied to session drop or a table argument at every use.
- Measured use: `Symbol`/`Name` appears in 40 files; `n("...")` has about 200 call sites and `.as_str()` far more. The type is used from the multi-threaded build (`ms-build`, `ms-clif`) where a scoped session table would also need propagating to workers.
- Measured: after checking the whole standard library the table holds 20,524 symbols and 534 KB of text. Generated binding ids repeat across re-checks (per-checker counters), so growth is per distinct identifier, not per edit.
- Recommendation: leave the interner process-wide, record the reason in the audit, and revisit only if the measurement shows real growth.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `ms-check/src/session.rs` (new), `stdlib.rs`, `checker.rs` | world and serial move into `Session`; free queries become methods | existing `ms-check` suite; new test: two sessions on one thread give independent worlds and uids |
| `ms-check/src/{hints,contracts,exprs,calls,editor}.rs` | read the world through `self.session` | `ms-check` golden and unit tests |
| `ms-lower/src/rtcall.rs`, `ms-lsp`, `ms-tooling/src/guide` | take the session from `Program` or own one | `cargo nextest run --workspace`, `make conform` |

## Alternatives

- Do nothing: no user-visible failure today. Cost is test and LSP code that must run on the loading thread and the serial's hidden coupling; judged worth removing because item 7 (`TyId` tables) needs the world to be a value, and tests and the LSP stop depending on which thread loaded it.
- Pass `&Std` as an extra parameter to every function (the audit's wording): same data, 60+ signatures change. A field on `Checker` plus `Program` reaches the same call sites with far less churn.
- Scoped-TLS session (rustc style): keeps hidden global access; rejected for the same reason as today's state.

## Stages

1. `Session` with the world and serial; `Checker` and `Program` carry it; thread-local and atomic deleted. Gate: `cargo nextest run --workspace`, clippy, `make conform`.
2. Consumers outside `ms-check` move to `program.session`; remaining `stdlib::` free-function calls removed. Gate: same, plus `make docs` output unchanged.
3. Interner measured and status of every cited item recorded in the audit.
