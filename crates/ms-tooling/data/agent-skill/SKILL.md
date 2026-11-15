---
name: manuscript
description: Write, check, test, and revise idiomatic Manuscript programs. Use for .ms source, Manuscript APIs, ownership, errors, streams, and compiler diagnostics.
---

# Write Manuscript

Generated for Manuscript {{MS_VERSION}}. Compare with `ms --version`; regenerate this skill with the matching compiler when stale. Manuscript is in beta: what the stability page lists is frozen; everything else may change.

## Core language

Use tabs for indentation. A trailing `:` opens a body; dedent ends it. A module contains imports and declarations; `main` is its entry point. Fields belong inside `type`; methods sit beside it with implicit `self`. `fn var` permits receiver mutation.

<!-- complete: skill-core.ms -->
```manuscript
type Counter:
	n: Int = 0

fn var Counter.add(value: Int) Void:
	self.n += value

fn Counter.value() Int: self.n

// ms: allow_effect std.console.write
fn main() Void!:
	value := "42".parse_int().ok_or(Error("expected an integer"))?
	var counter = Counter()
	counter.add(value)
	print(counter.value())
```

### Not Manuscript

Every row is a shape agents wrote that fails; the right column compiles.

| Not | Write |
| --- | --- |
| `!x`, `a ?? b`, `try f()`, `x or return y` | `not x`, `a.get(b)`, `f()?`, `if v := x:` then use `v` |
| `x.len`, `x.length`, `x == none` | `x.length()`, `x.is_none()` |
| `const X = 1`, `# note`, `pass` | `X := 1`, `// note`, `unit` |
| `a if c else b`, `-> T` | `if c: a else: b`, `fn f() T:` |
| `if c: f() else: g()` as a statement | `if c:` and `else:` on their own lines, bodies indented |
| `fn f(out: var T)`, `x: T = e` | `fn f(var out: T)`, `x: T := e` |
| `"\"{x}\""`, `"{"`, `"\x01"` | plain quotes inside `{}`, `"\{"`, `"\u{1}"` |
| `for _ in xs`, `unit := e` | `for _i in xs`; `unit` is a literal, never a name |
| `(String, Int)`, `[A, B]` tuples | a record: `type Pair:` with fields |
| `f(x)?` as a statement on a non-Void result | `_ := f(x)?` |
| `r?.abs()` on a Result | `(r?).abs()`; `?.` is for Optionals only |
| `m.contains_key(k)`, `xs.remove_last()` | `m.contains(k)`, `xs.pop()` |
| `set.insert(x)`, `r.is_err()`, `s.find(t)` | `set.add(x)`, `r.is_error()`, `s.index_of(t)` |

### Syntax and data

- Immutable: `x := e`, or `x: T := e`. Mutable: `var x = e`; assignment and content mutation require var. Basic types: Int, Float, Bool, String, Void; literals: `true`, `false`, `unit`. Strings interpolate `"hello {name}"`.
- Functions declare parameter/return types: `fn f(x: Int, n: Int = 1) Int:`. Call `f(2, n: 3)`. Inline bodies return expressions; multiline bodies use `return`. Void/Void! may fall through. Main returns Void, Int status, or Void!.
- Generics: `fn identity[T](x: T) T: x`. Callback: `fn(Int) Int`; closure: `fn x: x + 1`.
- Control: `if`/`else if`/`else`, `while`, `for x in xs:`, `for i in 0..n:` (excludes n), `break`, `continue`; `and or not`. Prefer early exits: `if c: return x`. Expression: `if c: a else: b`.
- Import `name` with `import name from "./other.ms"`; `export` shares declarations. Standard paths start `@std/`. Construct records `Counter()` or `Counter(n: 2)`. Receiver methods satisfy matching interfaces; no impl blocks.
- `enum Choice:` declares cases `Empty` and `Value(n: Int)`. Construct `Choice.Value(2)`. `match choice:` uses arms `Empty:`, `Value(n):`, or `_:`; match exhaustively and keep it flat.
- Prelude collections: `[1, 2]`, `Map[String, Int]()`, `Set[Int]()`. List pipeline: `xs | .filter(fn x: x > 0) | .map(fn x: x * 2) | .sum()`. `x | f(a)` passes x first; `x | .m()` calls a method. Map `.get(k)` returns Optional; `.get_or(k, default)` supplies a fallback.

### Absence, errors and ownership

- `T?` is Optional: values convert, `none` is absent. Extract with `if x := optional:` or `.get(default)`. `a?.field` chains absence; postfix `?` is for Results only.
- `T!` is Result[T, Error]. Return `ok(value)`/`error(Error("message"))`; `r?` extracts success or returns the error from a compatible Result-returning function. Otherwise `if x := r:` handles success; in else, `r.err()` yields the error directly (`.message` reads its text). Never call it on success or accidentally drop a Result.
- Int/Float/Bool copy. Owned values can be borrowed by reads and moved into storage. Clone only for an independent owner, e.g. `names.append(user.name.clone())`. `fn add(var xs: List[Int]) Void` is called `add(var xs)`; return parts of parameters by borrow without a marker. A binding made from part of `xs` (`it := xs.get(0, d)`, `for x in xs`) borrows `xs`: do not change `xs` while it lives, or end the initializer with `.clone()`. A function returns a part of its argument by borrow; otherwise build a new value with `.clone()`. Closeable cleans up at scope end unless moved; no GC.
- `p.wait()` on Promise[T] returns T! once; no async/await keywords. Keep mutable state with one owner. Effects use narrow directives above functions, as shown; directives do not execute effects.

### Standard calls

<!-- calls:start -->
Exact calls, most used first (from the declarations; `ms search_symbol <name>` shows the rest):

- String: length() Int; parse_int() Int?; split(String, Int?) List[String]; chars() List[String]; contains(String) Bool; slice(Int, Int) Result[String, Error]; starts_with(String) Bool; trim() String; fields() List[String]; index_of(String) Int?; trim_end() String; replace(String, String) String; ends_with(String) Bool; lines() List[String]
- List: get(Int, T?) T; length() Int; append(T) Void; clone() List[T]; contains(T) Bool; slice(Int, Int) Result[List[T], Error]; join(String) String; sort() Void; entries() List[ListEntry[T]]; remove(Int) Void; index_of(T) Int?; keys() List[Int]; sorted() List[T]; replace(Int, T) T
- Map: get(T) U?; length() Int; clone() Map[T, U]; contains(T) Bool; get_or(T, U) U; add(T, U) Void; entries() List[MapEntry[T, U]]; remove(T) Void; keys() List[T]
- Set: length() Int; clone() Set[T]; contains(T) Bool; add(T) Void; remove(T) Void
- Optional: get(T?) T; is_none() Bool; is_some() Bool; ok_or(E?) Result[T, E]; map(fn(T) U) U?
- Result: get(T?) T; err() E; map(fn(T) U) Result[U, E]; is_ok() Bool; is_error() Bool
- Int: to_int() Int; compare(Int) Int; abs() Int; to_float() Float
- Float: compare(Float) Int; abs() Float; to_string() String

Imports (a name must be imported unless it is in the prelude):

- `import stdin, stdout from "@std/io/io.ms"`
- `import collect, lines, read_all from "@std/io/streams.ms"`
- `import bit_and, bit_not, bit_or, bit_xor, floor, pow, shift_right, shift_right_unsigned, wrapping_add, wrapping_multiply from "@std/math/math.ms"`
- `import Bytes from "@std/bytes.ms"`
<!-- calls:end -->

## Deep dives

- [Program structure](references/program-structure.md): modules, imports, main, types, receiver methods.
- [Values and control](references/values-and-control.md): bindings, literals, branches, loops, ranges.
- [Types and functions](references/types-and-functions.md): signatures, generics, callbacks, enums, interfaces.
- [Errors and optionals](references/errors-and-optionals.md): absence versus failure, propagation, nested results.
- [Ownership and cleanup](references/ownership-and-cleanup.md): borrows, moves, clones, mutation, cleanup, borrow errors.
- [Collections and pipelines](references/collections-and-pipelines.md): construction, lookup, mutation, method and function pipelines.
- [Effects and concurrency](references/effects-and-concurrency.md): effects, promises, streams, capture.
- [Servers and state](references/servers-and-state.md): `serve` handlers cannot share mutable state; one owner promise and a pipe.
- [Validation](references/validation.md): checks, tests, diagnostics, habits from other languages.

## Verify

Run `ms check --fix <file>` first; it applies mechanical repairs. Run applicable `ms check`, `ms run` and `ms test` commands after editing. Check behavior, not just compilation; report unrun checks. Include imports. Prelude collections, Optional, Result, Error and print need none. For additional APIs, `ms search_symbol <words>` supplies signatures/imports; do not guess.
