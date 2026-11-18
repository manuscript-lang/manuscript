---
name: manuscript
description: Write, check, test, and revise idiomatic Manuscript programs. Use for .ms source, Manuscript APIs, ownership, errors, streams, and compiler diagnostics.
---

# Write Manuscript

Generated for Manuscript {{MS_VERSION}}. Compare with `ms --version`; regenerate this skill with the matching compiler when stale. Manuscript is in beta: what the stability page lists is frozen; everything else may change.

Manuscript is small, explicit and value-oriented: records and enums hold data, functions hold behavior, errors and absence are values, and every value has one owner. Read [Idioms](references/idioms.md) before writing: it holds thirteen complete programs to copy. Use exact names from [Standard calls](references/standard-calls.md).

## Write it this way

- **Data:** a `type` for facts, an `enum` for states, `match` covering every case. Defaults and named arguments instead of builder code.
- **Transformation:** a pipeline (`xs | .filter(f) | .map(g) | .sum()`) to derive values; a `for` loop to build a Map or change a `var`. A named function beats a one-use closure.
- **Ownership:** reading borrows; changing needs `var` at the declaration and at the call; storing moves. `.clone()` is for a real second owner and costs time and memory: borrow, move at the last use, or keep an index first.
- **Short forms:** `print(x)`, not `stdout().write`. `0..n`, `[0].repeated(n)`, `.map`, `.filter`, `.any`, `.all`, `.sum()`, `xs.extend(ys)` instead of loops that build or accumulate. `x := if c: a else: b`, `m.get_or(k, d)`, `s.is_empty()`, `a.max(b)`, `for _round in` for an unused name, `"""` for multi-line text.
- **Failure:** `T!` for what can fail, `return ok(v)` / `return error(Error("what"))` (not `return Error(...)`), `?` to propagate, and in a test `f()?` to read a Result, `.ok_or(Error("what and which input", kind: "EINVAL"))` to turn absence into an error. `T?` when absence is normal; unwrap with `if v := o:` or `.get_or(default)`. Do not write `call().get()` as a statement (it faults on error): use `call()?` (`main` may return `Void!`), or `void call()` to ignore the outcome.
- **Waiting:** no `async`. A waiting call returns a Promise already running; start several, `wait_all` them. Streams are read with `for line in stream | lines`. Share state through one owner and a pipe.
- **Tests:** `test "name":` blocks beside the code, run by `ms test`.

## Changing existing code

Read the file, its tests and `ms.toml` first, and match the style around you. Add an enum case, then let `ms check` list every `match` that must handle it. (`--fix` does not write the arms; add them by hand.) Change a signature, then fix each call the checker reports. Keep the change small, run `ms check --fix`, `ms test`, then `ms verify`. Add a `test` for the behavior you changed.

## Syntax card

Use tabs for indentation. A trailing `:` opens a body; dedent ends it. A module contains imports and declarations; `main` is its entry point. Fields belong inside `type`; methods sit beside it with implicit `self`; `fn var` permits receiver mutation.

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

- Bindings: `x := e` (immutable, `x: T := e`), `var x = e` (mutable). Types: Int, Float, Bool, String, Void; literals `true`, `false`, `void`.
- Functions: `fn f(x: Int, n: Int = 1) Int:`, called `f(2, n: 3)`. An inline body is an expression; a multiline body uses `return`. Closure: `fn x: x + 1` where a callback type is known; bound to a variable, type it: `f := fn(n: Int) Int: n * 2`. Generics: `fn id[T](x: T) T: x`.
- Control: `if`/`else if`/`else`, `while`, `for x in xs:`, `for i in 0..n:` (excludes n), `break`, `continue`, `and or not`. Early exits: `if c: return x`. Expression form: `if c: a else: b`.
- Collections need no import: `[1, 2]`, `Map[String, Int]()`, `Set[Int]()`. `m.get(k)` is Optional; `m.get_or(k, d)` has a fallback; `m.filter(fn k, v: v > 0)`, `m.map(fn k, v: ...)` and `m.retain(...)` take a key and a value parameter. `String.slice(a, b)` is a plain String (only `List.slice` is a Result). `Optional.get()` without a default is a lint error in `ms verify` even after an `is_none()` check: unwrap with `if v := o:` or `get_or`. `xs.get(i)` on a List is not Optional (it faults out of range): use `xs.get_or(i, d)`. `xs.slice(a, b)` returns a Result that is an error when `b` is past the end (no clamping), so `.get_or([])` silently gives an empty list: skip a header with `xs.slice(1, xs.length()).get_or([])`.
- Imports: `import name from "./other.ms"` and `import sqrt from "@std/math/math.ms"`; `export` shares a declaration; `ms search_symbol <name>` prints a name's import line.
- `enum Choice:` with cases `Empty` and `Value(n: Int)`, built `Choice.Value(2)`, matched with arms `Empty:`, `Value(n):`, `_:`. Keep `match` flat.
- Text: `"plain"` never interpolates (braces are literal), `f"total {n}"` interpolates, `r"\d+"` is raw, `"""` and `r"""` open multi-line text on the next line.
- Effects: narrow directives above functions, as in the example; they do not run effects. `ms check` ignores effects; `ms verify` reports each one a function reaches (`std.console.write`, `std.fs.read`, `std.fs.write`, `std.net...`) and the message names the exact directive to add.
- Not in the language: no `~ & | ^ << >>` operators (`bit_and`, `bit_or`, `bit_not`, `shift_left`, `shift_right` from `@std/math/math.ms`); no `let ... else`; no `assert` (import `expect_equal`, `expect_true` from `@std/test/test.ms`, call with `?`), no `x is Case` (use `match`), no static or constructor methods (`Store.new()`; write a free function `new_store()`), `fn var` on a free function (only methods; use `var` on the parameter), no `export` on methods (they travel with the type; a method must be declared in its type's module). An unused `match` binding is an error: write `_name`. Closeable values clean up at scope end; there is no GC.

## Compiler rules

Four rules cover most compiler errors; an error that names one is that rule.

1. **One owner.** `price.add(sku.clone(), 0)` then `stock.add(sku, n)`. "Moved here but used again" means clone at the store. While a binding borrows from `xs` (`it := xs.get(0, d)`, `for x in xs`), do not change `xs`.
2. **`?` unwraps a Result or an Optional.** It leaves the function on error or absence: the function must return a matching Result, or an Optional/`Void` for an Optional. `s.parse_int()` is `Int?`: `s.parse_int().ok_or(Error("bad number"))?` in a `Result` function. A Result is never dropped; `_done := f(x)?` when its value is unused. `r?.abs()` unwraps then calls.
3. **Names are exact.** Never translate: `xs.append(x)` not `push`, `contains` not `contains_key`, `pop` not `remove_last`, `is_error` not `is_err`, `x.length()` not `x.len`, `x.is_none()` not `x == none`. An Optional needs no wrapper: `return value`, never `some(value)` (absent is `none`).
4. **Shapes are fixed.** A body goes on indented lines after a `:` header. `for _i in xs` (a bare `_` is no name). Records, not tuples; `List[Int]`, not `List<Int>`; `not x`, not `!x`. Reserved words (`type`, `test`, `fn`, `var` ...) are never names.

## References by task

- Start here: [Idioms](references/idioms.md) (thirteen complete programs), [Standard calls](references/standard-calls.md) (every prelude call, exact), [Standard modules](references/standard-modules.md) (which `@std` module exports which names, for imports).
- Language: [Program structure](references/program-structure.md), [Projects, ms.toml and packages](references/projects-and-packages.md), [Values and control](references/values-and-control.md), [Types and functions](references/types-and-functions.md).
- Data and failure: [Collections and pipelines](references/collections-and-pipelines.md), [Errors and optionals](references/errors-and-optionals.md), [Ownership and cleanup](references/ownership-and-cleanup.md).
- Concurrency and services: [Effects and concurrency](references/effects-and-concurrency.md), [Servers and state](references/servers-and-state.md).
- Checking: [Validation](references/validation.md) (tests, diagnostics, a wrong/right table of habits from other languages).

## Verify

Run `ms check --fix <file>` first; it applies mechanical repairs but does not format: run `ms fmt` before `ms verify`. Pass program arguments after `--`: `ms run main.ms -- in.json out.json`. Run applicable `ms check`, `ms run` and `ms test` commands after editing. Check behavior, not just compilation; report unrun checks. Include imports. Prelude collections, Optional, Result, Error and print need none. For additional APIs, `ms search_symbol <words>` supplies signatures/imports; do not guess.
