+++
title = "Source guarantees and representations"
weight = 94
+++

# Source guarantees and representations

A machine value must keep the behavior its Manuscript type promises: `Int` arithmetic detects overflow and values do not alias unless the program asks. The compiler and runtime enforce what raw machine values do not.

| Source guarantee | Lowering |
| --- | --- |
| Checked `Int` | `i64` with checked operations that fault on overflow |
| Valid UTF-8 `String` | Validated construction and conversion; header, length, bytes |
| Records and collections | Heap objects with a 16-byte header; explicit `.copy()` duplicates |
| Tagged alternatives | Header, tag, and a payload sized to the largest case; exhaustive frontend checking |
| Optional and `Result` | Null pointer or `{ present, value }`; tag plus payload |
| Value equality and hashing | Direct comparison for scalars, strings, handles; otherwise `eq`, `hash`, `clone` entries in a compiler-emitted element descriptor |
| Explicit contract implementation | Frontend selection of a unique implementation, then `{ data, vtable }` views |
| Closures | Closure objects with snapshot captures |
| Lexical cleanup | `with` registrations and close calls; see [cleanup lowering](cleanup-and-faults.md) |

## Representation boundaries

- Locals, captures, arguments, and results have their own machine representations ([design contract](https://github.com/manuscript-lang/manuscript/blob/main/crates/DESIGN.md#value-representation-word-level-64-bit-targets)); nothing is boxed. Exact layouts and symbols are in `crates/ms-rt/ABI.md`.
- Int division and remainder overflow, Float non-finite results, Decimal underflow and overflow, and checked truncation follow [runtime numeric outcomes](../../../core-language/basics/numbers-and-booleans.md#runtime-numeric-outcomes).
- Explicit [view constructors](../../../core-language/types/contracts.md#explicit-contract-views) create ordinary contract views.
- Check [recursive storage rules](../../../core-language/types/records.md#recursive-data) in the frontend, before lowering.

See [type checking](../frontend/type-checker.md) and [scope and capture checking](../frontend/scope-checker.md).
