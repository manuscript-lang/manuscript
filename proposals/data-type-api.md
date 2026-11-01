# Data type API shape: indexing, aggregates, replace, Optional/Result, parsing, JsonValue

## Summary

- An audit of the data types (`/mnt/project-files/review/data-types-audit-2026-10-25.md`) found the runtime close to Rust but the API uneven: `[]` works only on List, sorting always takes a comparator, `replace` means "first", `Result.or_else` unwraps while `Optional.or_else` does not, parsing is split between a method and `@std/math/math.ms`, free functions duplicate methods, and `JsonValue` has no accessors.
- Change: `m[k]`, `m[k] = v`, `bytes[i]`; `sorted()`/`sort()`/`sum()`/`min()`/`max()` on List; `replace` replaces all occurrences; `Result.map_error`, `get_or_else` on both Optional and Result; `String.parse_float`; remove duplicate math functions and `Set.entries`; `JsonValue` accessors written in Manuscript.
- Cost: one checker/lowering rule for index targets, one stdlib migration (`replace`), docs and corpus updates. No new type or keyword.
- Decision: Chinmay approved Map/Bytes indexing and the `replace` change on 2026-10-25 (card "Both"). Chinmay also delegated the remaining naming calls on 2026-10-25 ("feel free to fix issues that you think you have a better idea"), so `Result.or_else` is renamed to `get_or_else` here.

## Status

Proposal, 2026-10-25, checked against `bf26f78c`. Direction (Chinmay, 2026-10-25): "i want these to be extremely fast and intuitive to use"; card answer "Both" to "Allow `m[k]`/`bytes[i]` indexing and make `replace` mean all occurrences?".

## Problem

Verified with `ms check` on `bf26f78c`:

- `m["a"]`: `type: indexing requires List[T]; read a Map entry with m.get(key)`. `m["b"] = 2`: `resolution: unknown or ambiguous member set on Map[String, Int]; 'm[key] = value' assigns only into a List`. `data[i]` on Bytes: `indexing requires List[T]; use the receiver's lookup method for other types`. `wiki/language/index.md` ("indexing returns the element") records `[]` for List, String and Bytes.
- `[3, 1, 2].sorted()`: `missing argument compare: Callable[[Int, Int], Int]`. `xs.sum()`, `xs.max()`: unknown member. `math.max_of` needs `Comparable & Clonable` and is a free function (taste: methods first).
- `String.replace(old, new, max_replacements)` replaces the first occurrence and is documented as a "transitional compatibility name"; `replace_first`, `replace_n`, `replace_all` are three more spellings. Python's `replace` replaces all, so agent code such as `line.replace(",", "")` handles one comma.
- `Result.or_else(create: Callable[[E], T]) -> T` returns a payload; `Optional.or_else(create: Callable[[], Optional[T]]) -> Optional[T]` returns an alternative. `Result.map_error` does not exist (`unknown or ambiguous member map_error`).
- `"12".parse_int() -> Optional[Int]` is a method; `parse_float(text) -> Result[Float, NumberError]` and `parse_int(text, radix)` are free functions in `@std/math/math.ms`.
- `@std/math/math.ms` exports `abs`, `abs_int`, `sign`, `sign_int`, `to_float32`, each the same as a method on the receiver (`stdlib/intrinsics.ms`).
- `Set.entries() -> List[List[T]]` copies every element twice into a JavaScript shape; nothing in `stdlib/` or `tests/` calls it.
- Reading `doc.user.name` from a `JsonValue` is one `match` per level (`stdlib/json.ms` has no `impl JsonValue`), which the nested-`match` rule forbids.
- Non-goals: `s[i]` on String (scalar indexing is O(n) on non-ASCII text; `for c in s.chars()` is the fast spelling), slices by `[]`, a mutable byte buffer, `Optional.filter` (rejected before: diagnostic names `map`, `and_then`, `if let`), iterator protocols.

## Design

### Indexing

- `m[k]` on `Map[K, V]` reads the value for `k` as a borrow, like `xs[i]`; an absent key faults with the key's text: `map key not found: "a"`. `m[k] = v` is `m.add(k, v)`; `m[k] += 1` reads then adds, faulting when absent (it is `m[k] = m[k] + 1`). Requires `var m` as `add` does.
- `bytes[i]` reads a byte as `Int`; negative indexes count from the end; out of range faults as List does.
- `get(key)` / `get(index, default:)` stay the non-faulting forms; docs show `[]` for the known-present case and `get` otherwise.

```manuscript
var counts = Map[String, Int]()
counts["a"] = 1
counts["a"] += 1
let n = counts["a"]           # 2; counts["zz"] faults
let data = "hi".to_bytes()
let first = data[0]           # 104
```

### List aggregates and natural order

- `sorted(compare: Optional[Callable[[T, T], Int]] = none) -> List[T]`: without a comparator, `T` must be `Comparable` (Int, Float, String, user types with `impl Comparable`); the diagnostic for a non-Comparable element names the comparator form. `sort(compare: ... = none) -> Unit` sorts in place (`var def`). Natural Int order keeps the existing `msrt_list_sort_ints` fast path.
- `sum() -> T` on `List[Int]` and `List[Float]` (and sized numerics); overflow faults as `+` does. `min()`/`max() -> Optional[T]` for `T: Comparable`; `none` on an empty list. `math.max_of`/`min_of` are removed in favor of the methods.
- Bodies in Manuscript where the element type allows (`sum`, `min`, `max` as loops in `stdlib/collections.ms`); `sorted()` without a comparator lowers to the existing native sort with the built-in comparison.

### `replace`

- `replace(old: String, new: String) -> String` replaces every nonoverlapping occurrence; an empty `old` matches at each scalar boundary (today's `replace_all` rule). `replace_first(old, new) -> String` replaces one. `replace_n` and `replace_all` are removed; `max_replacements` and `max_bytes` go (the string allocation limit faults as `concat` does).
- Migration: every `replace_all(a, b).get(...)` and `replace_all(a, b) | try` becomes `replace(a, b)`; `replace(a, b)` meaning "first" becomes `replace_first(a, b)`. `Regex.replace_all`/`replace_template` are unchanged (different receiver; Regex is explicit about matching).

### Optional and Result

- Add `Result.map_error[F: Error](transform: Callable[[E], F]) -> Result[T, F]`.
- Rename `Result.or_else(create: Callable[[E], T]) -> T` to `get_or_else`, and add `Optional.get_or_else(create: Callable[[], T]) -> T`. `Optional.or_else` keeps its lazy-alternative meaning; `Result.or_else(create: Callable[[E], Result[T, E]]) -> Result[T, E]` is added so the two types match: `get` and `get_or_else` return the payload, `or_else` returns the same wrapper, `map`/`and_then`/`map_error` transform.

### Parsing and numeric duplicates

- `String.parse_float() -> Optional[Float]` beside `parse_int`, same rules as `math.parse_float` (`none` where it returns an error). `math.parse_float`/`parse_int(radix)` stay for the `Result` and radix forms.
- Remove `math.abs`, `abs_int`, `sign`, `sign_int`, `to_float32`; the methods are the one spelling.

### JsonValue accessors

In `stdlib/json.ms`, written in Manuscript:

```manuscript
impl JsonValue:
    fn get(key: String) Optional[JsonValue]      # ObjectValue member, else none
    fn at(index: Int) Optional[JsonValue]        # ArrayValue element, else none
    fn as_string() Optional[String]
    fn as_int() Optional[Int]                    # NumberValue text that parses as Int
    fn as_float() Optional[Float]
    fn as_bool() Optional[Bool]
    fn as_list() Optional[List[JsonValue]]
    fn as_map() Optional[Map[String, JsonValue]]
```

`doc.get("user").and_then(lambda u: u.get("name")).and_then(lambda n: n.as_string()).get("")` replaces three nested matches. Results borrow where the payload is a String, List or Map (`-> ref Optional[...]`) if the checker allows it for alternative payloads; otherwise they clone and the doc comment says so.

### Removal

- `Set.entries()` is removed; `for v in s` and `s.values()` remain.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `crates/ms-syntax` | index assignment target already parses; diagnostic text for Map targets | conformance |
| `crates/ms-check` | `[]` on Map and Bytes; `m[k] = v`, `m[k] op= v`; `sorted`/`sort` default comparator bound; new members | conformance accept/reject |
| `crates/ms-lower` | index read/write on Map via `msrt_map_get_ptr`/`add`; Bytes read via `msrt_bytes_get`; natural-order sort | e2e |
| `crates/ms-rt` | fault text for absent map key; `replace` natives renamed | unit tests |
| `stdlib/collections.ms`, `intrinsics.ms`, `core.ms`, `math.ms`, `json.ms`, `string.ms`, `bindings.json` | declarations above | `tests/e2e/testdata/stdlib/*.ms` |
| formatter, LSP | unchanged (no new syntax) | existing |
| `documentation/core-language/types/collections.md`, `basics/text-and-bytes.md`, `errors/results.md`, `types/optionals.md` | rules | `make docs-check`, `make book-check` |
| `wiki/language/index.md`, `stdlib-design.md` | indexing and `or_else` entries updated | reference check |
| `bench/agent/challenges/*/solutions/ms/main.ms.ref`, `tests/conformance` | `replace` migration | `make conform`, workloads run |

## Alternatives

- Do nothing: agents keep writing `m.get(k).get()` and `line.replace(...)` with Python's meaning; the audit's three string-heavy workloads stay the slowest because the convenient spellings copy.
- `m[k]` returning `Optional[V]`: rejected before for List (`at` removal, `wiki/language/index.md`); `[]` faults, `get` does not, one rule for every receiver.
- Keep `replace_all` as the all-occurrences name and remove `replace`: leaves the Python footgun's opposite (a missing method) and two names for the common case.
- A `sum` free function in `math`: taste says methods first; `max_of` is the precedent being removed.

## Staging and verification

1. Indexing (`crates/ms-check`, `ms-lower`, docs, corpus). Gate: `make verify`, `make conform`, e2e fixture with the fault texts.
2. List aggregates and natural sort. Gate: stdlib fixture, `list.sorted` bench unchanged.
3. `replace` migration. Gate: `make conform`, workloads run with identical output.
4. Optional/Result additions and rename. Gate: stdlib fixture, corpus.
5. Parsing method and math duplicate removal. Gate: `ms search_symbol abs_int` finds nothing; docs regenerated.
6. JsonValue accessors. Gate: stdlib fixture; `json.parse` bench unchanged.
7. `Set.entries` removal. Gate: docs and corpus.

Each stage is one PR with auto-merge and a regression fixture.

## Open questions

None: the owner approved the indexing and `replace` changes by card and delegated the remaining naming decisions (2026-10-25). The `Result.or_else` rename supersedes the `unwrap_or_else` entry in `wiki/stdlib-design/index.md`, which the implementing PR updates.
