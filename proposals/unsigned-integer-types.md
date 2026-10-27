# Unsigned integer types

## Summary

- Add `UInt8`, `UInt16`, `UInt32` and `UInt64`, extending [sized numeric types](sized-numeric-types.md), which left unsigned types out of scope and said `Bytes` wants `UInt8`.
- Byte data is the motivating case: `Bytes.get`, `values()` and `append` use `Int` for a value that is 0 to 255, so `toml.ms` needs a `-1` end-of-input sentinel (about 31 `Bytes.get(..., default:)` sites in `stdlib/`: toml 20, yaml 6, jsonstream 2, streams 2, router 1; about 89 test files use `Bytes` get/values/append) and nothing stops `append(300)` until run time.
- **Cost:** four more primitives, a signedness bit in the layout and conversion tables, and unsigned MIR ops for `UInt64` only. `Int` and every existing program are unchanged; the `Bytes` migration in stage 3 is the only breaking stage.
- No `Byte` alias. An alias would print as `UInt8` in diagnostics anyway (the prelude-alias idea is already rejected in the parent proposal), so `UInt8` is the one spelling.

## Status

Implemented (stages 1 to 4). Deviations from the draft: `truncate_to_uintN()` was dropped (floats convert through `truncate_to_int()`); `Bytes` is plain `Bytes` over `UInt8` with no type parameter; the `toml.ms` sentinel became a `byte_at` helper returning `Optional[UInt8]`; `UInt64` add, subtract, multiply, divide, remainder, compare, formatting and `to_float` are runtime calls (and ordered `icmp` flips the sign bit) so no optimizer or backend pass needed unsigned ops. Draft written against `7da646f4`. Direction (Chinmay, 2026-10-27): "the right fix here is just to add unsigned types to the language", after #1546 (`Bytes.get` returning `UInt8`).

## Problem

- `Bytes.get(index, default: Optional[Int]) -> Int` returns 0 to 255 as an `Int`. `toml.ms:147-156,196,256,390` encodes "no byte" as `-1` because `Int` is the only type that holds both.
- `bytes.ms` `uint8`, `uint16_*` and `uint32_*` return `Int` because no type spells "0 to 2^n - 1". `toml.ms` also compares bytes against untyped constants (`let TAB = 9`, `b < 32`), which become `UInt8`.
- A `List[Int8]` holds -128 to 127, so packed bytes today need `Int8` plus manual `& 0xff`-style conversion, or 8 bytes per byte.

## Design

### Types and registers

- Four primitives in the prelude with `Int8`..`Int64`. MIR gains `TyKind::UInt8`, `UInt16`, `UInt32`, `UInt64`.
- Registers stay `i64`. `UInt8`, `UInt16` and `UInt32` hold their value zero-extended (0 to 2^n - 1), so signed compare, divide, remainder and shift are already correct for them; a `narrow.chk` against the range `[0, 2^n)` after each arithmetic op keeps them in range. This reuses the stage 1 mechanism with a lower bound of zero.
- `UInt64` holds its bit pattern in the `i64`. It needs unsigned variants of exactly these ops: compare, divide, remainder, add/sub/mul overflow detection (carry, borrow, `umulhi`), conversion to `Float`, decimal formatting and parsing. They are selected by the operand's MIR type, as `narrow.chk` already selects its width; no new surface syntax.
- The extern ABI is unchanged: every unsigned value crosses a call as an `i64` word. A `UInt64` above `i64::MAX` is a negative `i64` bit pattern, so a native taking one must treat it as unsigned; the only such natives are the ones this work adds.

### Semantics

- **Arithmetic.** Same-type operands. `+ - *` fault when the result leaves `[0, 2^n)`, so `a - b` faults when `b > a`. `/` and `%` fault on a zero divisor; there is no `MIN / -1` case. Unary `-` on an unsigned operand is a compile error naming the type.
- **Literals.** The contextual rule extends to unsigned types: `let b: UInt8 = 200` works, `256` and any negative literal are compile errors naming the range. The checker already parses literals through `i128` (`exprs.rs:114`), so `UInt64` literals up to 18446744073709551615 fit; the lowering constant path must emit the bit pattern, and the range diagnostic (`exprs.rs:386-392`, hardcoded `-half..half-1`) is reworked to take signedness.
- **Conversions.** Same shape as the signed ones: `to_uint8()` .. `to_uint64()` on every integer receiver, returning the target type when every source value fits (`UInt8.to_uint16()`, `UInt8.to_int16()`, `UInt32.to_int64()`, `UInt8.to_float()`) and `Optional[Target]` otherwise (`Int.to_uint8()`, `UInt64.to_int64()`, `Int8.to_uint64()`). Floats get `truncate_to_uint8()` .. `truncate_to_uint64()`. `to_float`, `to_decimal`, `compare`, `to_string_radix` exist on every unsigned type; `abs` and `sign` do not (`sign` of an unsigned is `0` or `1` only, so it is omitted; use `compare`).
- **Equality, hashing, ordering.** Same-type only. `compare` and `List.sort` order unsigned by value; this needs per-type runtime comparison for `UInt64`, since a signed compare orders values above `i64::MAX` first.
- **Memory.** `UInt8` and `UInt16` and `UInt32` pack to 1, 2, 4 bytes in lists, records and optionals with a zero-extending load. Today `Leaf::N8/N16/N32` always sign-extend (`ms-clif/src/lower.rs:182,291,299`, `cg.rs:106,116`), so stage 1 adds unsigned leaves `U8/U16/U32` and extends the union payload tables that assume seven leaf kinds (`layout.rs:300`, whose `.expect("payload leaf kind")` would panic). `UInt64` reuses `I64`. `UInt64` is 8 bytes. Map slots stay word-sized, as for the signed types.
- **Formatting.** `to_string`, interpolation and `to_string_radix` print the unsigned value; `UInt64` above `i64::MAX` is the reason it needs its own formatting path.

### Example

```manuscript
let data = Bytes.from_string("hi")
let first: UInt8 = data.get(0, default: 0)
let next = first + 1          # UInt8; faults at 255 + 1
let wide: Int = first.to_int()  # widening is infallible
let narrow = wide.to_uint8()  # Optional[UInt8]
```

Rejected:

```manuscript
let a: UInt8 = 256   # error: literal 256 is out of range for UInt8 (0 to 255)
let b: UInt8 = -1    # error: literal -1 is out of range for UInt8 (0 to 255)
let c = -first       # error: unary - is not defined for UInt8
```

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `ms-check` | four primitives, `int_bits`/range with signedness (`types.rs:523`, `exprs.rs:114-127,386`), `builtin_comparable` list (`contracts.rs:~166`, else generic `Comparable` and `sort` fail), unary minus rejection, receivers | conformance accept/reject per type |
| `ms-mir` | four `TyKind`s, `scalar_kind`/`int_bits` (`types.rs:239-275`), `verify.rs:587`, interpreter `NarrowChk`/`INarrowOpt` ranges (`interp.rs:543-566`, symmetric today), unsigned ops for `UInt64` | MIR interpreter tests |
| `ms-lower` | `external.rs`, `eq.rs:323`, `cx.rs`, `expr.rs` tables; `rtcall.rs:116` shares the `int` prefix across widths, so `UInt64` gets its own (compare, to_string, radix, to_float, parse) | `make conform` |
| `ms-clif`, LLVM | zero-extending loads, unsigned `icmp`/`udiv`/`urem`/overflow for `UInt64`, descriptors | e2e on Linux, macOS, Windows |
| `ms-rt`, `ms-rt-abi` | descriptors (`cg.rs:412` routes sized ints to POD; `UInt64` needs an explicit decision), signed `msrt_int_compare` (`num.rs:486`) stays, unsigned compare/sort/hash, format and parse for `UInt64` | runtime unit tests, leak check |
| `stdlib/*.ms`, `bindings.json` | `UIntNOperations` interfaces, `sum()` per list type, then `Bytes` migration | `make docs` |
| `ms-tooling` guide (`guide/api.rs`), formatter, LSP, docs | type names, completion, `numbers-and-booleans.md` | LSP test, book check |

## Alternatives

- **Do nothing.** Keeps `-1` sentinels and unchecked byte values; rejected by the owner.
- **`UInt8` only.** Fixes the sentinel and `append(300)` and avoids every `UInt64` hazard. `UInt16`/`UInt32` have no consumer beyond `uint16/32_*` readers, which already work as `Int`; `UInt64` has no in-repo consumer (`bytes.ms` has `int64_*` only). Including them is a policy choice by the owner ("uints and other friends"), not evidence-driven; stage 2 (`UInt64`) is separately droppable.
- **`UInt8`..`UInt32` only, no `UInt64`.** The 64-bit type is the one that needs new unsigned ops. It is staged last so it can be dropped if its cost exceeds its use. Recommendation: build it, because hashes and a future `uint64_le` reader want it; those would be new API.
- **Wrapping `Byte` type.** Rejected; the language faults on overflow everywhere.

## Drawbacks

- Four more types and conversion methods; mixing `Int` and `UInt8` needs explicit conversions at every boundary (`b.to_int()` for indexing, `Int` → `UInt8` is `Optional`).
- `Bytes` migration breaks every caller that treats a byte as `Int`.
- A `UInt64` above `i64::MAX` is a negative `i64` in the runtime, so any native that forgets the unsigned rule misorders or misprints it.

## Staging and verification

1. **`UInt8`, `UInt16`, `UInt32`.** Checker, MIR, lowering, layout with zero-extending loads, packed lists/records/optionals, contextual literals, conversions and receivers, `sum()`. Gate: `make conform`, runtime tests per width, packed `List[UInt8]` memory measurement.
2. **`UInt64`.** Unsigned MIR ops, literal range, formatting/parse, compare/sort/hash, Cranelift and LLVM. Gate: values above `i64::MAX` through arithmetic, compare, sort, print, parse, `to_float` on both backends and all platforms.
3. **`Bytes` and stdlib migration.** `get`, `values`, `append`, `with_value`, `index_of_byte`, `uint8/16/32` readers and `append_uint*` (`uint64` only if stage 2 lands), other `Bytes` users; replace the `toml.ms` `-1` sentinel with `Optional[UInt8]`; update tests. Gate: `make verify-full`.
4. **Docs.** Numbers page, conversion table, generated reference, changelog.

## Open questions

- Should `Int.to_uint8()` and friends be `Optional`, or should a checked cast fault? Recommendation: `Optional`, matching the signed narrowing conversions.
- Bitwise operators and shifts are not language operators today (`msrt_bits_*` externs); not added here.
