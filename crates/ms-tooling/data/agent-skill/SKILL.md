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

### Rules

Five rules cover the errors agents hit most. Apply them before writing; a compiler error that names one is that rule. Wrong and right shapes side by side: [Validation](references/validation.md).

1. **One owner.** A String, List, Map or record has one owner. Reading, comparing and passing as an argument borrow it. Storing it (`m.add(k, v)`, `xs.append(x)`, `m[k] = v`, `Node(name: x)`) moves it, so a name used again after the store is stored as `x.clone()`: `price.add(sku.clone(), 0)` then `stock.add(sku, n)`. While a binding borrows from `xs` (`it := xs.get(0, d)`, `for x in xs`), do not change `xs`.
2. **Absence and failure are values.** `T?` is unwrapped with `if v := o:` or `o.get(default)`. `T!` is unwrapped with `r?` inside a function that returns a Result, else `if v := r:`. `?` is only for Results: `s.parse_int()` is `Int?`, so write `s.parse_int().ok_or(Error("bad number"))?`. A Result is never dropped: `_done := f(x)?` when its value is unused.
3. **Names are exact.** Use the calls in [Standard calls](references/standard-calls.md), which lists every String, List, Map, Set, Optional, Result, Int and Float call; for any other, run `ms search_symbol <words>`. Never translate from another language (`contains_key`, `is_err`, `sort_by`, `.len`).
4. **Shapes are fixed.** A `:` ends a header and the body is the indented lines after it; `if c: a else: b` is an expression only. `x := e` binds, `var x = e` changes. A parameter the callee changes is `var x: T` in the declaration and `f(var x)` at the call. `for _i in xs` (a bare `_` is no name), records not tuples, `List[Int]` not `List<Int>`, `not x`, `x.length()`, `x.is_none()`.
5. **Text has four forms.** `"plain"` never interpolates, so braces are literal; `f"total {n}"` interpolates; `r"\d+"` is raw; `"""` and `r"""` open multi-line text that starts on the next line and closes on a line of its own.

### Syntax and data

- Immutable: `x := e`, or `x: T := e`. Mutable: `var x = e`; assignment and content mutation require var. Basic types: Int, Float, Bool, String, Void; literals: `true`, `false`, `void`. `f"hello {name}"` interpolates; plain `"{"` keeps braces.
- Functions declare parameter/return types: `fn f(x: Int, n: Int = 1) Int:`. Call `f(2, n: 3)`. Inline bodies return expressions; multiline bodies use `return`. Void/Void! may fall through. Main returns Void, Int status, or Void!.
- Generics: `fn identity[T](x: T) T: x`. Callback: `fn(Int) Int`; closure: `fn x: x + 1`.
- Control: `if`/`else if`/`else`, `while`, `for x in xs:`, `for i in 0..n:` (excludes n), `break`, `continue`; `and or not`. Prefer early exits: `if c: return x`. Expression: `if c: a else: b`.
- Import `name` with `import name from "./other.ms"`; `export` shares declarations. Standard paths start `@std/`. Construct records `Counter()` or `Counter(n: 2)`. Receiver methods satisfy matching interfaces; no impl blocks.
- `enum Choice:` declares cases `Empty` and `Value(n: Int)`. Construct `Choice.Value(2)`. `match choice:` uses arms `Empty:`, `Value(n):`, or `_:`; match exhaustively and keep it flat.
- Prelude collections: `[1, 2]`, `Map[String, Int]()`, `Set[Int]()`. List pipeline: `xs | .filter(fn x: x > 0) | .map(fn x: x * 2) | .sum()`. `x | f(a)` passes x first; `x | .m()` calls a method. Map `.get(k)` returns Optional; `.get_or(k, default)` supplies a fallback.

### Absence, errors and ownership

- `T?` is Optional: values convert, `none` is absent; `a?.field` chains absence. `T!` is Result[T, Error]: return `ok(value)` or `error(Error("message"))`; `r?` returns the error from a compatible function. In an else branch of `if x := r:`, `r.err()` yields the error (`.message` is its text). `x?` on a Result in `r?.abs()` needs parentheses: `(r?).abs()`.
- Int/Float/Bool copy. `fn add(var xs: List[Int]) Void` is called `add(var xs)`; a function returns a part of its parameters by borrow with no marker, else a new value (`.clone()`). Closeable cleans up at scope end unless moved; no GC.
- `p.wait()` on Promise[T] returns T! once; no async/await keywords. Keep mutable state with one owner. Effects use narrow directives above functions, as shown; directives do not execute effects.


## Deep dives

- [Program structure](references/program-structure.md): modules, imports, main, types, receiver methods.
- [Values and control](references/values-and-control.md): bindings, literals, branches, loops, ranges.
- [Types and functions](references/types-and-functions.md): signatures, generics, callbacks, enums, interfaces.
- [Errors and optionals](references/errors-and-optionals.md): absence versus failure, propagation, nested results.
- [Ownership and cleanup](references/ownership-and-cleanup.md): borrows, moves, clones, mutation, cleanup, borrow errors.
- [Collections and pipelines](references/collections-and-pipelines.md): construction, lookup, mutation, method and function pipelines.
- [Effects and concurrency](references/effects-and-concurrency.md): effects, promises, streams, capture.
- [Servers and state](references/servers-and-state.md): `serve` handlers cannot share mutable state; one owner promise and a pipe.
- [Standard calls](references/standard-calls.md): every String, List, Map, Set, Optional, Result, Int and Float call, exact.
- [Validation](references/validation.md): checks, tests, diagnostics, habits from other languages.

## Verify

Run `ms check --fix <file>` first; it applies mechanical repairs. Run applicable `ms check`, `ms run` and `ms test` commands after editing. Check behavior, not just compilation; report unrun checks. Include imports. Prelude collections, Optional, Result, Error and print need none. For additional APIs, `ms search_symbol <words>` supplies signatures/imports; do not guess.
