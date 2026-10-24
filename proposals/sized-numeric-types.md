# Sized numeric types, with 32-bit `Int` and `Float`

## Summary

- Only `Int` (i64) and `Float` (f64) exist, so every number stored in a `List`, record or map takes 8 bytes.
- Add `Int8`, `Int16`, `Int32`, `Int64`, `Float32`, `Float64`, stored packed, and make `Int` mean `Int32`. `Float` stays `Float64`.
- **Cost: changing the default from 64 to 32 bits is a breaking semantic change.** It narrows overflow, literal ranges and every stdlib signature that returns or takes a 64-bit quantity (time, file sizes, hashes, lengths), and it changes `Float` precision from about 15.9 to 7.2 decimal digits.
- Review outcome: the flip has no memory measurement yet, and `Float32` as default is the weakest part. Recommendation: `Int = Int32`, `Float = Float64`.
- Decision (Chinmay, 2026-10-24): `Int = Int32`, `Float = Float64`. Stage 5 (the `Int` flip) is the only breaking stage and stays gated on a `bench/` measurement.

## Status

- Approved 2026-10-24 for staged implementation with `Int = Int32` and `Float = Float64` (card answer "Int32, Float64"). Written against `df8ebe59`. Stages 1 to 4 implemented 2026-10-24. Stage 5 (the default flip) dropped by the owner 2026-10-24 (card answer "Keep Int as Int64"): `Int` stays `Int64`, sized types are explicit. Skeptical review: done 2026-10-24; findings folded in below (review ran on the first draft).
- Direction (Chinmay, 2026-10-24): "lets add specific number types in the stdlib, we need to have 8, 16, 32, 64 style numeric types so we can reduce memory usage, default to 32 for Int/Float".

## Problem

- `Int` is i64 and `Float` is f64 everywhere: `TyKind::Int`/`TyKind::Float` (`crates/ms-mir/src/types.rs:43,45`), `i64`/`f64` in `crates/ms-clif/src/layout.rs:11-12,255-256`, `Int` in `crates/DESIGN.md:30`.
- A `List[Int]` of byte values, a record of small counters, or a `Map[String, Float]` of ratios spends 8 bytes per number. Lists store elements `desc.size` bytes apart (`crates/ms-rt-abi/src/lib.rs`, `Vec`), so a narrower element type reduces memory without a new container.
- There is no way to state a range in a type: a pixel channel and a file offset are both `Int`.
- Not measured: the memory saved on any real workload, and in particular what the default flip saves. Stage 3 measures `List[Int8]`; stage 5 additionally needs a `bench/` measurement of flipped programs before it is proposed for merge.

## Goals and non-goals

- Goals:
  - Integer and float types at 8, 16, 32 and 64 bits (floats at 32 and 64), packed in lists, records, maps and optionals.
  - `Int` and `Float` stay the unannotated defaults and become 32-bit.
  - One rule for all widths, with no per-width special cases in the checker or lowering.
- Non-goals:
  - Unsigned types (see Open questions), `Int128`, arbitrary-precision (`BigInt` stays in `@std`), `Decimal` (unchanged).
  - Implicit widening or narrowing. Conversions stay explicit, as today (`numbers-and-booleans.md`).
  - Platform-sized `Int` on 32-bit targets: the fixed width replaces "64 bits on 64-bit targets, 32 on 32-bit targets".

## Design

### Types

- Six primitives: `Int8`, `Int16`, `Int32`, `Int64`, `Float32`, `Float64`. They are in the prelude with `Int` and `Float`.
- `Int` is an alias of `Int32` and `Float` an alias of `Float64`. The alias is one entry in the checker's primitive table (`crates/ms-check/src/types.rs` `primitive`), not a second type: `Int` and `Int32` are the same type everywhere, including diagnostics.
- MIR (as implemented in stage 1): `TyKind::Int8`, `Int16`, `Int32` and `Float32` join `Int` (64-bit) and `Float`. `Int` stays the 64-bit kind; stage 5 changes which checker name maps to it, not the MIR kind.
- Registers: every integer is an `i64` and every float an `f64` in registers and calls, whatever its width. A sized integer is kept in range by a `narrow.chk` op after each arithmetic op, with the width read from the operand's MIR type. A `Float32` is kept rounded by the `f32.round` op. Only storage (stage 3) changes the width.
- Consequence: the extern ABI, runtime natives, the Windows adapter and the LLVM translator keep passing `i64` and `f64`; no `f32` or narrow integer crosses a call boundary. This replaces the earlier plan of per-width register types.

```
             before                      after
  Int  --- i64, 8 bytes         Int = Int32 --- i32, 4 bytes
  Float -- f64, 8 bytes         Float = Float64 -- f64, 8 bytes (unchanged)
                                Int8/16/64, Float64 --- packed to their width
```

### Semantics

- **Arithmetic.** Operands must have the same type (existing rule). `+ - *` and unary `-` fault when the result leaves the type's range; `/` truncates toward zero; the zero divisor and `MIN / -1` fault; `MIN % -1` is zero. These are the current `Int` rules with the range parameterized.
- **Float.** `Float32` rounds each operation to binary32, ties to even, no fused multiply-add. Overflow, NaN and comparison rules are the current `Float` rules.
- **Literals.** A literal has the type `Int` (or `Float`) unless the expected type is a sized numeric type, in which case it has that type and is range-checked there. This is the same expected-type mechanism `none` and `[]` use (`optionals.md`, `records.md`), applied to numeric literals, and it relaxes "expected types never change a literal's type"; it flows through `Optional[Int8]`, `List[Int8]` and record fields, not through generic inference. It is needed so `let x: Int64 = 5` and `Int8` field initializers work without suffixes. A literal that does not fit is a compile error, naming the type and range.
- **Conversions.** Widening is infallible and narrowing is checked:
  - `to_int8() ... to_int64()`, `to_float32()`, `to_float64()` on every numeric receiver. A conversion that cannot lose information returns the target type; one that can returns `Optional[Target]` (`none` when out of range, matching `truncate_to_int`).
  - Float to integer keeps `truncate_to_int()`, generalized to `truncate_to_int8()` ... `truncate_to_int64()`.
  - `to_float()` and `to_decimal()` remain, defined on every integer type.
- **Equality, hashing, ordering.** Same-type only. `Int32` keys in maps hash by value; `Int64` and `Int32` are different key types.
- **Memory.** Packed width applies in lists, record fields, map keys and values, and optionals. A record of `Int8, Int32, Int8` follows the existing record layout rules (alignment padding); the proposal does not add field reordering.
- **Native ABI.** Sized values cross extern calls as `i64` and `f64` words (see Types), so no narrow integer or `f32` reaches a calling convention and the Windows adapter is unaffected. A native receiving a sized value that was not range-checked cannot exist: only checked values are produced.

### Examples

Before and after for an unannotated program:

```manuscript
let big = 3_000_000_000      # accepted before; compile error after: Int is Int32
let ok: Int64 = 3_000_000_000
let samples: List[Int8] = [1, 2, 3]
let total: Int32 = 0
for s in samples:
    total = total + s.to_int32()   # no implicit widening
```

Rejected, with the intended diagnostic:

```manuscript
let a: Int8 = 200
# error: literal 200 is out of range for Int8 (-128 to 127)
let b: Int32 = 1
let c: Int64 = 2
let d = b + c
# error: operands must have the same type: Int32 and Int64; convert with to_int64()
```

## Components touched

| Component | Change | Risk / test |
| --- | --- | --- |
| `crates/ms-syntax` | none; type names are identifiers | unchanged |
| `crates/ms-check` | six primitives, alias table, contextual numeric literals, per-type range check, conversion methods in `receivers.rs`/`stdlib.rs`, operator table | conformance accept/reject per width |
| `crates/ms-mir` | `TyKind::Int(Width)`, `TyKind::Float(Width)`; interpreter wraps/checks per width (`interp.rs`) | MIR interpreter tests per width |
| `crates/ms-lower` | `number`, `rtcall`, `native`, `mathops` read `Width`; no new lowering for existing ops | `make conform` |
| `crates/ms-clif`, LLVM | `layout.rs` size, align, `I8..I64`/`F32,F64`; overflow ops per width; descriptors `msrt_desc_int8..` | e2e fixtures on all platforms |
| `crates/ms-rt`, `ms-rt-abi`, `ms-rt-hot` | element descriptors for new widths; map probes for `Int32` keys (map slots are word-sized today, so keys and values stay word slots in v1 and only lists and records pack); `Optional` payload tag per width; sort, hash, `msrt_int_compare`, `msrt_float_compare`, `msrt_float_truncate_to_int`, `msrt_numbers_parse_int` and number formatting per width | runtime unit tests per width; leak check |
| `crates/ms-std-*`, `stdlib/*.ms`, `bindings.json` | signatures that need 64 bits become `Int64` (stage 5); `@std/math` stays binary64; `Float32` callers convert explicitly with `to_float64()`, no overloads | `make docs`, `ms search_symbol` |
| `stdlib/bytes.ms` | `Bytes.get`, `values()` stay `Int`; `UInt8` is deferred, so this is a known inconsistency | documented |
| `stdlib/bindings.json` | `"Int": "IntOperations"` receiver table gains one entry per width, generated from one declaration | `make docs` |
| formatter, lint, LSP, VS Code | type names, hover and completion for conversion methods; a diagnostic hint for literals over 2^31 after the flip | LSP completion test |
| `documentation/core-language/basics/numbers-and-booleans.md` and `expressions.md` | tables, range text, conversion table, literal rule | `make docs`, example checks |
| `tests/conformance` | accept/reject per width, overflow per width, literal ranges | all three platforms; no platform gating |

## Breaking cost of the default flip (stage 5)

- **Overflow.** `Int` faults at 2,147,483,647. Programs that sum, multiply or count past 2^31 fault where they ran before; this is a programming fault, not a compile error, so existing code can fail at run time.
- **Literals.** `3_000_000_000` and every literal outside the 32-bit range become compile errors; code needs `Int64`.
- **Float.** Unchanged: `Float` stays binary64, so `@std/math`, `Decimal.to_float` and JSON numbers keep their results. `Float32` is opt-in.
- **Stdlib surface.** `length()` and indexes stay `Int` (lists above 2^31 elements are not supported), but these must be re-typed `Int64` or they truncate: `Duration`/`Instant` nanoseconds (64-bit by the current spec; the `.seconds`/`.milliseconds` members take `Int`, so with a 32-bit `Int` the source count is limited to about 68 years of seconds but only about 24 days of milliseconds), file sizes and offsets in `@std/fs`, `hash()` in `core.ms:160`, `@std/random`, `@std/time`, byte counts in `@std/io`, `@std/net`. The inventory is 740 `Int` mentions in `stdlib/*.ms` and 48 `"Int"`/`"Float"` string checks in 18 files under `crates/` (`grep -rn '"Int"\|"Float"' crates`); each needs a decision, not a search-and-replace.
- **Existing programs and benchmarks.** Everything in `bench/` and `tests/conformance` that uses `Int` as 64-bit changes meaning. Benchmark numbers move in both directions (smaller data, more sign-extension for indexing); none of this is measured.
- **Mitigation.** Stages 1–4 add the types with `Int = Int64` (and `Float = Float64` throughout) and change no existing behavior. The flip lands last, as one PR, so it can be reverted or dropped.

## Alternatives

- **Do nothing.** Keeps 8 bytes per number and no range types. Zero cost; does not meet the request.
- **Float32 default.** Rejected by the owner (2026-10-24): halves float storage but changes precision to ~7 digits and every `@std/math` result.
- **Sized types only, default stays 64-bit (stages 1–4).** Delivers the memory reduction for anyone who writes `List[Int8]`, with no break. Does not meet "default to 32". Smallest version that proves the benefit; recommended stopping point if stage 5 is not approved.
- **`Int = Int32`, `Float = Float64`.** Halves default integer storage and keeps float precision and `@std/math` unchanged. Breaks overflow and literal ranges only. Chosen by the owner.
- **Platform-sized `Int`.** Already the documented text for 32-bit targets, but behavior differing by target breaks the parity rule and was never implemented.
- **Suffixed literals (`5i8`).** Rejected for the first version: contextual literal typing covers the cases with no lexer change.
- **Generic `Int[N]`.** More general, but needs const generics, which the language does not have.

## Drawbacks

- More types to learn, and explicit conversions at every width boundary; the common case `Int` is unchanged in spelling.
- Literal inference gets one exception (contextual numeric literals).
- Packed elements need alignment-correct loads and stores in lists, sort, maps and the runtime; the inline-string work showed that missed reads become wrong-bytes bugs, so every runtime native that reads elements needs a per-width test.
- The flip silently converts working programs into runtime faults.
- Prior art: Rust and Zig default `i32`-style literals but require explicit types; Go's `int` is platform-sized; Swift's `Int` is word-sized; Python and Java use fixed 32/64 splits. A 32-bit default with 64-bit time and sizes is the Java model, which is known to need `long` threading through APIs.

## Staging and verification

1. **Types, no layout change (implemented).** Checker names, ranges, contextual literals (including the other operand of an operator), `narrow.chk` and `f32.round`, `Float32` printing (`msrt_float32_to_string`), `msrt_fault_int_range`; conversions are not part of it. Six primitives and aliases (`Int = Int64`, `Float = Float64`). Existing programs behave identically. Gate: `make conform` new accept/reject cases.
2. **Conversions and receivers (implemented).** New MIR ops `conv` (widen int, or float rounding to nearest-even, infallible) and `inarrow.opt` (narrowing int to `Optional[Target]`). `Int.to_int64()` is an identity for the alias. `to_int8()` ... `to_float64()`, `compare`, `to_string_radix`, `to_decimal` on every width via `bindings.json` and `intrinsics.ms`. Native codegen needs no stage of its own (see Types).
3. **Packed storage (implemented).** Memory leaves `N8/N16/N32/F32` in `ms-clif/src/layout.rs`; `Int8..Int32` descriptors are `POD`, `Float32` is `msrt_desc_float32`; number literals also take a sized constructor-field or `Optional.get` default type. Measured on 50M appends, release: `List[Int8]` 49 MB 0.04 s, `List[Int32]` 195 MB 0.12 s, `List[Int]` 391 MB 0.21 s. Lists, records, maps, optionals use the width; runtime sort, hash, equality per width. Gate: runtime unit tests per width, leak check, and a measurement of `List[Int8]` against `List[Int]` for memory and time.
4. **Stdlib and docs (`abs()`/`sign()` methods implemented; `Int64` retyping moves to stage 5, where it first changes behavior).** Math conversions, `Int64` where quantities need it, generated reference. Gate: `make docs`, `make verify`.
5. **Default flip.** Prerequisite: a `bench/` run of flipped programs against stage 4. Alias `Int` to `Int32` (`Float` stays `Float64`), update stdlib signatures and literal ranges, migrate tests and benchmarks. Gate: `make verify-full`, `bench` comparison against stage 4, explicit owner approval after reading that comparison.

## Open questions

- Resolve before approval (decider: Chinmay):
  - Float default: resolved, `Float = Float64` (owner, 2026-10-24).
  - Approve the contextual numeric literal rule? Recommendation: yes.
  - Unsigned types (`UInt8` ... `UInt64`)? Recommendation: out of scope here; add later with the same `Width` plumbing, since byte data (`Bytes`) wants `UInt8`.
  - Which stdlib quantities become `Int64` in stage 5? Recommendation: time, file sizes and offsets, `hash`, random, net/io byte counts.
  - Math without casts (owner question, 2026-10-24). Generic bounds exist (`stdlib/math.ms:262` `max[T: Comparable]`), so `min`, `max`, `min_of`, `max_of` already work on every width once each width implements `Comparable`. `abs`, `sqrt`, `pow` and the rest cannot be generic: a generic body is checked against its bounds only (`generics.md`, "checked once"), has no operator bounds and no static constructors, so it cannot do arithmetic or call a per-width native on `T`. Recommendation: (1) `abs` and `sign` become receiver methods on each integer and float width, declared once; (2) transcendental functions stay `Float64`, which is the default `Float`, so only explicit `Float32` users call `to_float64()`; (3) no operator-interface or specialization mechanism in this proposal.
- Resolve during implementation: conversion method naming (`to_int64()` against `Int64(x)`), record field reordering for padding (recommendation: no).

## Rejected ideas

- A prelude `type Int = Int32` alias: general, but diagnostics would print `Int32`; deferred, the alias is one primitive-table entry either way.
