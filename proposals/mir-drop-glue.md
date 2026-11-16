# Drop functions for records and enums are written in MIR

## Summary

- Problem: each backend writes its own drop code for a record or an enum (Cranelift `lower/glue.rs`, LLVM `glue_llvm.rs`), including which cases own something, which are borrowed, and how the shared payloadless block of a boxed enum is skipped. Two copies of one language rule can disagree.
- Change: a MIR pass makes one drop function per type, and both backends call it.
- Decision requested: none; this is the first stage of the direction "language logic in MIR, backends only lower".

## Status

Proposal, 2026-11-16, checked against `e0fab5d0`. Stage 1 of the audit in the thread "Move language logic out of the backends into MIR". Clone functions, optionals, lists, interfaces, and types that contain themselves stay in the backends for now.

## Problem

- The drop of an enum is a walk over its cases: skip a borrowed case, drop each owned field, free the block unless the case is a shared payloadless block. Cranelift writes it in `glue_drop_alt`, LLVM in `drop_alt`; the record walk and the boxed-record block release are written twice as well.
- Equality and hash functions are already MIR (`Module::desc_glue`, built in `ms-lower/src/eq.rs`), so drop is the odd one out.

## Design

- `ms_mir::glue::run` runs after `expand` and before `expand_owned`. It finds every record and enum type a value of the program can have, and for those that need a drop and cannot reach themselves, it makes a function whose body is `type.release` (record) or a switch on the tag with one `alt.release` per case (enum). `expand_owned` then lowers the release shorthands like everywhere else.
- `Module::drop_glue` maps a type to its function. `Gen::glue` in both backends returns that function for `Glue::Drop` instead of queueing their own body. The LLVM backend keeps these functions on the leaf calling convention so callers name one symbol.
- The `Glue` kinds and the glue name prefix move to `ms_mir::glue`; both backends had identical copies.
- The verifier skips these functions: they are written after ownership elaboration and some paths do not consume the parameter in the way its rules ask.

## Alternatives considered

- Do nothing: the two copies stay and can drift; every later change to enum layout needs two edits.
- Generate every kind of drop (lists, optionals, interfaces, self-containing types) at once: needs a stack-depth op and list loops in MIR, which other threads are adding; one large PR is harder to check.
- Generate the body from primitive ops directly: needs the same release lowering that `expand_owned` already has, so it would copy it.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `ms-mir` | `glue` pass, `Module::drop_glue`, verifier skip | conformance corpus on both backends |
| `ms-clif`, `ms-mir-llvm` | use the MIR drop function; shared `Glue` kinds | conformance corpus, `cargo test` for both crates |
| `ms-build` | run the pass | corpus |

## Measurement

Against `e0fab5d0` on a generated 1,000-module project (a record and an enum per module): release build 19.1 s to 15.0 s (median of 5), check 0.23 s to 0.29 s median with equal minimum (0.21 s and 0.19 s), debug build 1.87 s to 1.81 s. Ten suite programs run at equal speed within noise (for example `interp`, 11 alternating runs: median 0.228 s base, 0.223 s new).
