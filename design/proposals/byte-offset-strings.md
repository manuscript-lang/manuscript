# Byte-offset strings (Rust style)

Status: proposal, 2026-11-14. Direction from Chinmay: "okay let's do rust style" (after the options in `scalar-index-cache.md`, which this supersedes). Changes user-visible behavior, so the migration plan below needs his approval.

## Summary

- Problem: `length`, `get`, `scalar_at`, `slice`, `view`, `index_of` and `last_index_of` count Unicode scalars, which UTF-8 cannot locate in O(1). A loop over indexes of large non-ASCII text is quadratic (189k scalars: `get(i)` for every i 5.5 s, `while i < s.length()` 2.3 s at b308b8cf).
- Change: positions are byte offsets, O(1), and always on a scalar boundary; characters are walked with `chars()` or `scalars(text)`. No integer scalar index into text.
- Decision requested: approve the API table, the removal of `get`, and the in-place meaning change of `length`.

## Today

- `documentation/core-language/basics/text-and-bytes.md` already says there is no `text[index]`, that `get` walks from the start, and points to `scalars(text)` (`@std/text.ms`) for constant-time stepping.
- ASCII strings are O(1) through the `STR_ASCII` flag; only text with a non-ASCII scalar pays. Rust (`chars().nth`) has the same cost; Go and Rust slice by bytes.

## Design

| Operation | Today | Proposed |
| --- | --- | --- |
| `length()` | scalars | bytes, O(1); `byte_length()` is removed (one term per concept) |
| `scalar_length()` | scalars | unchanged, O(n), named so |
| `slice(a, b)`, `view(a, b)` | scalar bounds | byte bounds; a bound inside a scalar is `ERANGE` (`view`: fault), like Rust's boundary panic |
| `index_of`, `last_index_of` | scalar index | byte offset, so `slice(i, ...)` takes it directly |
| `get(i)` | one-scalar String | removed; use `chars()` or `scalars(text)` |
| `scalar_at(i, default)` | by scalar index | by byte offset: the scalar starting there; not a boundary gives the default |
| `slice_scalars` | scalar bounds | removed (`slice` now covers the use) |
| `take(n)`, `drop(n)` | scalar counts | removed: mixed with byte `length` they break (`s.drop(s.length())`); `slice`/`view` and `chars()` cover them |
| `pad_start`, `pad_end`, `count("")` | scalar counts | unchanged and documented as scalar counts: O(n) once, no index loop |
| `find_char`, `index_any` | scalar index | byte offset, like `index_of` |
| negative bounds | relative to the end | unchanged (add `byte_length`) |

- ASCII text behaves exactly as before, so most programs and tests do not change; non-ASCII results change meaning.
- Stepping by offset needs the width of the scalar at an offset: `scalar_at(i)` plus a plain UTF-8 width of that code point.
- `length()` becomes the one O(1) size name for text and `Bytes`; `is_empty` unchanged.

- Regex matches and `Bytes.decode_utf8_range` already use byte offsets; this removes the one mismatch with `String` (stronger evidence than the benchmark).
- `scalars(text)` copies through `to_bytes()` and `scalar_width` is private (`stdlib/text.ms`); make the width a public `Int` method so offset stepping needs no copy. Diagnostic columns (YAML `column:`) stay in scalars: compute them with `scalar_length()` of the line prefix.

## Components

- `ms-rt/string.rs`, `utf8.rs`: `msrt_string_slice`, `view`, `index_of`, `last_index_of`, `scalar_at` take byte offsets; the scalar scans (`scalar_offset`, `advance`, `retreat`) lose their callers; `msrt_string_length` returns the byte length.
- `ms-lower/native/method.rs:176` maps `length` to `scalar_len`: it becomes the `byte_length` field read; `scalar.rs`/`fuse.rs` code-point fusion keyed on `get` moves to `scalar_at`; `ms-check/hints.rs` and `stmts.rs:1583` hints that suggest `get` change.
- `ms-lower/rtstr.rs`: inline `length` becomes a field read for every string, not only ASCII; byte slicing needs only a boundary test of two bytes.
- `stdlib/core/intrinsics.ms`, `stdlib/core/string.ms`, `stdlib/text.ms` and every stdlib body that indexes text (`fields_by`, `title_word`, `find_char`, formatters, parsers).
- Docs: `text-and-bytes.md`, generated reference, agent skill text; wiki page on text units.
- Tests and fixtures: those that index non-ASCII text.

## Evidence required before building

- Measured: the baseline above and a re-run after (`bench/perf/string-pass`, a new `index_loop` case with a Rust `s[i..]`/`chars().nth` twin).
- Not measured yet: how many call sites change meaning. Method: apply the change, run `ms-conform`, stdlib tests and `make verify`; every failure is a non-ASCII site. `get` removal makes the checker list its uses.

## Alternatives

1. Do nothing: stays quadratic on large non-ASCII text.
2. Scalar index cache (`scalar-index-cache.md` option 3): keeps scalar indexing, adds an allocator hook and silent-wrong-text risk.
3. Go style: `s[i]` returns a byte; half characters leak into ordinary code.
4. UTF-16 or fixed-width storage (V8, Python): O(1) index but a representation change and more memory.
5. Keep `length()` in scalars and add `byte_length` use: leaves `while i < s.length()` quadratic, the common idiom.

## Risks

- Silent meaning change of `length`, `slice`, `index_of` for non-ASCII text in user programs. Mitigation: the version is 0.1.0, the change goes in the release notes, and the docs carry the migration; the checker cannot tell statically which strings are non-ASCII.
- Boundary errors: `slice` on a non-boundary byte offset is `ERANGE`; programs that built offsets by arithmetic must use `index_of` or `chars()`.

## Open questions

- Keep `scalar_at`, or drop it too and rely on `chars()`?
- Name of the public scalar width method on `Int`.
- Resolved after review: `take`/`drop` removed rather than kept in a second unit.
