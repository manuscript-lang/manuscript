# Nullable types: `T?` is `T` or `null`, not a container

## Summary

- Problem: `T?` is an enum around `T`, so `Int??` is a different type from `Int?`, a borrowed element behind it needs a copy or a special view, and methods on `T?` clash with methods of `T`.
- Change: `T?` is the type `T` plus `null`. `T??` collapses to `T?`, `none` is renamed `null`, and a nullable has no methods (`x == null`, `x or d`, `if v := x`, `?`, `?.`).
- Decision requested: approve the three stages below. Stage 1 (collapse) ships first; the rename and the method removal follow as separate stages. This is stage one of [borrow-by-default-results](borrowed-results.md), issue #5404.

## Status

Proposal, 2026-11-23, written from issue #5404 (Chinmay, 2026-11-21: "nullability is attached to the type itself, not a separate container"; "let's just name it null"; "get rid of methods on it, similar to typescript"; "use `or`, not `??`"). Chinmay asked on 2026-11-23 to start. Not implemented. Skeptical review: see the end.

## Problem

- Today `T?` is an invariant enum and `Int??` differs from `Int?` (`documentation/core-language/types/optionals.md`). A lookup returns the enum, so a borrowed payload needs a copy or a view, and a boxed optional cannot be a view.
- `Int??` is almost never what a user wants. A scan of `tests`, `stdlib` and `examples` for a written `T??` finds 29 `.ms` files (13 under `e2e`, 16 `snippets` including `-fmt` copies; a raw `??` grep gives 35, an upper bound) and no type in `stdlib/` (`json.ms` matches only in doc comments); JSON encoding of `Int??` needed its own shape-table fix (#6526).
- `x.get_or(d)` is ambiguous when `T` has its own `get_or` (`Map.get_or(key, d)` on a `Map[K, V]?`), and `map` over a callback returning `U?` nests, which is why `and_then` exists.

## Design

**`T?` means "a `T`, or `null`". There is one empty value and no layer to peel.**

```manuscript
fn first_or_null(xs List[Int?]) Int? {
    return xs.first() or null
}

fn main() Void {
    a Int? := 3
    b Int? := null
    print(a != null)
    print(b == null)
}
```

- Collapse: `T??` is `T?` wherever it arises, written or by generic instantiation (`fn first[T](xs: List[T]) T?` with `T = Int?` returns `Int?`). A written `T??` gets a diagnostic with a fix to `T?`.
- A plain `T` passes where `T?` is expected, as today. `Int?` and `Int??` are one type, so the "wraps exactly one layer" rule goes.
- `null` takes its type from the expected type, as `none` did. `if v := x`, `x?`, `a?.b`, `match` arms, `is_some` and `ok_or` keep their meaning until stage 3.
- Absent and stored `null` are the same to `get`; `has` still separates a missing key from a stored `null` in `Map[K, V?]`.
- Ownership: a nullable follows its `T`. Owned `T?` owns the value or nothing; a borrowed `T?` borrows the place or is `null`. `Result[T, E]` stays an enum.
- Layout is not language: a type with a spare pattern (a pointer) stores `null` in it, other types keep a presence flag. The shape table (`MS_SHAPE_NULLABLE`, flagged optionals) already has both; collapse removes the nested-flag case.
- Equality and hashing: two `null` are equal, `null` differs from every present value, `null` hashes to a fixed constant.

## Stages

1. **Collapse.** `Optional` is a prelude enum with one argument, not a type kind, and is built in several places (`parse_type.c` for `T?` and `Optional[...]`, `check/exprs.c`, `check/instantiate.c`, `lower/lower_func.c`; 56 `MS_BUILTIN_Optional` and 82 `MK_OPT` sites, many assuming one wrapped layer). First fold those into one helper; collapse where a type is instantiated, so `Optional[Int?]` and a generic `T = Int?` collapse too; then add the `T??` diagnostic. The helper, the collapse and the deletion of `nested_optional` in `mir_shape_table.c` are separate commits. Check: `ms check` of every `Int??` fixture; the nested-optional paths in lowering and the shape table (`nested_optional`, flagged optionals inside flagged optionals) are deleted once nothing builds them. Fixtures that assert two layers (`optional-arguments`, `generic-optional-callbacks`, `result-error-values`, `optional-methods`, `recursive-types`, the checker and compiler snippets) are rewritten to the collapsed meaning.
2. **Rename `none` to `null`.** About 2,160 uses (issue count, `stdlib` 920, `tests` 1,101, `documentation` 141); one mechanical formatter pass in one commit. `null` stops being a rejected foreign word; `none` becomes the rejected word with a machine fix. `JsonValue.Null` is unrelated and stays.
3. **No methods on a nullable.** `x or d` replaces `get_or`, `get_or_else` and `or_else`, and runs the right side only on `null`; `== null` replaces `is_some` and `is_none`; `if v := x`, `?` and `?.` replace `map` and `and_then`; `ok_or` becomes a prelude function. Each removed method keeps a diagnostic naming its replacement for one release. Upper-bound counts on `58e5a1a9`: `get_or` 1,199, `is_none` 301, `is_some` 197, `or_else` 91, `ok_or` 62.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `src/compiler/check` type construction | build `T?` through one constructor that collapses a nullable `T`; diagnostic for a written `T??` | conformance: `T??` fix, generic instance with nullable `T` |
| `src/compiler/mir` shape table and layout | drop the nested flagged-optional case | `ms test` of json.ms and the optional fixtures |
| `src/compiler/lower` | borrowed `T?` as a nullable place pointer (stage 3 follow-up) | existing e2e |
| `stdlib/*.ms`, `documentation/` | stage 2 and 3 rewrites; `optionals.md` loses the enum and `Int??` paragraphs | `make docs`, conformance |

## Alternatives

- Do nothing: lookups keep a view type or copy, nested optionals stay, and the C port keeps the nested-flag shape code.
- Keep the enum and add a borrowed-optional kind: a second Optional type users must learn; rejected.
- Reject `T??`: breaks generic code over a nullable `T` and makes `Map[K, V?]` lookups unusable; rejected.
- Swift-style nested optionals: keeps the distinction, which Chinmay judged not worth it.

## Risks

- Behaviour change: a `none` stored in `Int??` becomes absent, and `Map[K, V?].get` no longer separates a missing key from a stored `null` (callers use `has`). Existing callers need an audit (`direct-collection-conversions.ms`, `collection-prelude.ms`); the fixtures that assert two layers change meaning, not just spelling.
- Stage 1 alone removes code (about 40 lines of nested flag handling) and a type; it delivers no measured speed or copy benefit. The borrowed-lookup benefit is stage 3 and lowering work. Stage 1 is therefore ordered with stage 3 in mind, not claimed as a win on its own.
- Function-value adapters build nested optionals with special close and drop paths (#4211); collapse keeps them correct.

## Stage 1 findings

- Generic code is the cost. `T?` with `T = Int?` is `Int?`, so a generic that wraps `T` as `T?` is the identity, and one that unwraps `T?` to `T` returns the value itself. Lowering handles both at the wrap (`fn_convert`), `if v := x` and `match` sites, and `ms_check_unify` accepts `T = Int` and `T = Int?` for the same `T?` pattern.
- A native that answers `T?` loses "present" when `T` is nullable. Map and List lookups hand back the stored value itself. Promise results cross as `Slot[T]` so a `none` result is not mistaken for a taken one. Stdlib generics that read a map value with `get(key).get()` use `self[key]` instead.
- `next() T?` protocols (iterators, pipes) end at `null`, so a stream of a nullable `T` ends at its first null. Nothing in the stdlib relies on the old behaviour.
- A `JSON` field of type `Int??` is just `Int?`: `null` is omitted, as a `none` field already is.

## Open questions

- A written `Int??`: diagnostic with a fix (recommended, since it is almost always a mistake) or silently accepted.
- Faulting unwrap (`get()`): recommend no `!` operator; write `x or fault(...)` or `if v := x`.
- `ok_or` and `ok_or_else`: recommend one prelude function `ok_or(x, cause)`.
