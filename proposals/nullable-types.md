# Nullable types: `T?` is `T` or `null`, not a container

## Summary

- Problem: `T?` is an enum around `T`. A borrowed element behind it (`xs.first()`, `m.get(k)`) forces a copy or a special view, and `Int??` is a different type from `Int?` that no user needs.
- Change: `T?` is the type `T` plus `null` (renamed from `none`). Nullability belongs to the type, so a borrowed `T?` is a borrowed `T` that may be absent, and `T??` is `T?`. The `?` spelling stays.
- Decision requested: approve collapse and the layout rule. It is the first stage of [borrow-by-default-results](borrow-by-default-results.md).

## Status

Proposal, 2026-11-21, checked against `58e5a1a9`. Not implemented. Direction (Chinmay, 2026-11-21): "we need the concept of nullable types, where the nullability is attached to the type itself, not a separate container"; absent and `none` are the same to a user, so `T??` collapses; "let's just name it null, it's more appropriate". `Result` keeps owning its contents. Skeptical review: not run yet.

## Problem

- Today `T?` is "an invariant enum" and "`Int??` differs from `Int?`" (`documentation/core-language/types/optionals.md`). A lookup returns the enum, so a borrowed payload needs `opt.view`, and a boxed optional cannot be a view (`wiki/language/results-borrow-parts-of-their-arguments-without-a-marker.md`). Lowering copies in those instances.
- A function whose `T` is itself nullable returns a nested type the caller must unwrap twice (`map` with a callback that returns `U?` keeps nesting; `and_then` exists to avoid it). Methods on `T?` also clash with the methods of `T`.
- Measured on `58e5a1a9`: the corpus uses nested optionals once (`tests/conformance/fixtures/snippets/golden/golden-0732.ms`, `Result[T, Error]??`, a parameter that is never read). Containers of nullable elements are in `stdlib/regex.ms`, `stdlib/data/json.ms`, `queue.ms`, `deque.ms`.

## Design

**`T?` means "a `T`, or `null`". There is one empty value and no layer to peel.**

```manuscript
fn first_or_none(xs: List[Int?]) Int?:
    return xs.first() or null

fn main() Void:
    a: Int? := 3
    b: Int? := null
    print(a != null)
    print(b == null)
```

- Collapse: `T??` is `T?` wherever it arises, written or by generic instantiation (`fn first[T](xs: List[T]) T?` with `T = Int?` returns `Int?`). A written `T??` gets a diagnostic with a fix to `T?`.
- A plain `T` passes where `T?` is expected, as today. An `Int?` fits `Int??` because they are one type; the "wraps exactly one layer" rule goes.
- Absent and stored `null` look the same to `get`. `has` still separates a missing key from a stored `null` in a `Map[K, V?]`.
- `null` takes its type from the expected type, as `none` did. `if v := x`, `x?`, `a?.b`, `match` arms (`v:` and `null:`), `get_or`, `is_some` and `ok_or` keep their meaning.
- Ownership: a nullable follows its `T`. Owned `T?` owns the value or nothing. A borrowed `T?` borrows the place or is `none`. `Result[T, E]` stays an enum, owns its error and follows the mode for its success value.
- Layout is not language: a type with a spare pattern (a pointer, a string with a non-null pointer) stores `null` in it; other types (`Int`, `Bool`, small records) store a flag beside the value. Hypothesis, to verify in `compiler/src/mir/mir_layout.c`: today's boxing decision for recursive optionals reduces to the pointer case.
- Equality and hashing: two `null` are equal; `null` differs from every present value; hash `null` as a fixed constant.

## No methods on a nullable

Direction (Chinmay, 2026-11-21): "get rid of methods on it, similar to typescript". A `String?` has no members of its own; you narrow it first.

- Why it fits: with `T?` as `T` or `null`, `x.get_or(d)` is ambiguous when `T` has its own `get_or` (`Map.get_or(key, d)` on a `Map[K, V]?`). Dropping the methods removes the clash.
- Test: `x == null` and `x != null` for any `T`, with no `Equatable` bound.
- Default: `x or d` (Chinmay, 2026-11-21: use `or`, not `??`). When the left side is a nullable, `or` returns it if present, else `d`; the right side runs only on `null`. It replaces `get_or`, `get_or_else` and `or_else`, and fixes `get_or` always evaluating its argument. `a or b or c` chains; a diverging right side (`x or fault(...)`) works. No new token. Only `null` triggers it: `0`, `false` and `""` stay present, unlike Python's `or`, which agents may expect otherwise. A non-nullable left side stays the Bool `or`; a `Bool?` left side is the nullable form, since there is no implicit unwrap.
- Narrow: `if v := x`, postfix `?` and `?.` stay, and replace `map` and `and_then`.
- Size on `58e5a1a9` (grep, includes same-named `Map` and `List` methods, so an upper bound): `is_some` 197, `is_none` 301, `get_or` 1,199, `get_or_else` 19, `or_else` 91, `and_then` 37, `ok_or` 62, `ok_or_else` 18. `ms lint --fix` rewrites each form; `x.map(f)` and `and_then` need a hand rewrite where the callback is not trivial.
- Each removed method keeps a diagnostic that names its replacement for a release.

## Rename `none` to `null`

- Size on `58e5a1a9`: about 2,160 uses (`stdlib` 920, `tests` 1,101, `documentation` 141, `examples` 1) A mechanical rewrite by the formatter, in one commit.
- `null` is today a rejected foreign word with a targeted diagnostic (`documentation/core-language/basics/grammar.md`); that entry is removed. `none` takes its place as the rejected word, with a machine fix to `null`. `JsonValue.Null` is a different spelling and stays.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `crates/ms-check` types, `compiler/src/check` (`MsTyTable`) | build `T?` through one constructor that collapses a nullable `T` | conformance: `T??` fix, generic instance with nullable `T` |
| `crates/ms-mir` and `compiler/src/mir` | a nullable is its payload type plus the none rule; delete `opt.view` for it once results borrow by default | `mir-diff`, verifier tests |
| Lowering | borrowed `T?` as a nullable place pointer; no copy at lookups | `make copy-check`, `make count-check` |
| `stdlib/*.ms` | nothing; remove optional methods, add `ok_or` function | existing e2e |
| Docs | rewrite the enum and `Int??` paragraphs in `optionals.md`; `OWNERSHIP.md` | `make docs-check` |

## Alternatives

- Do nothing: lookups keep a view type or copy, and nested optionals stay.
- Keep the enum and add a borrowed-optional kind: a second Optional type users must learn; rejected.
- Reject `T??`: breaks generic code over nullable `T` and makes `Map[K, V?]` lookups unusable; rejected.
- Swift-style nested optionals: keeps the distinction, which Chinmay judged not worth it.

## Stages

1. Collapse in the type constructor and the diagnostic. Check: `make conform`, `cargo test -p ms-check`.
2. Layout: niche or flag per type. Check: `make count-check`, MIR verifier.
3. Borrowed `T?` as a place pointer, with the borrow-by-default rule. Check: `make copy-check`.

## Open questions

- `ok_or` and `ok_or_else` turn a nullable into a `Result`. Recommend a prelude function `ok_or(x, cause)`, so 80 call sites do not become four-line `if` blocks.
- Faulting unwrap (`get()`): recommend no `!` operator; write `x or fault(...)` or use `if v := x`. Needs a diverging expression form; check what the language has.
- Moot with no methods: `is_some` and `is_none` become `!= null` and `== null`.
- Is a written `Int??` a diagnostic or silently accepted? Recommend a diagnostic with a fix, since it is almost always a mistake.
