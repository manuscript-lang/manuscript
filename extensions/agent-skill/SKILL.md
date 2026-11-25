---
name: manuscript
description: Write, check, test, and revise idiomatic Manuscript programs. Use for .ms source, Manuscript APIs, ownership, errors, streams, and compiler diagnostics.
---

# Write Manuscript

Written for Manuscript {{MS_VERSION}}. Compare with `ms --version`; when they differ, download the skill of your compiler's release. Manuscript is in beta: what the stability page lists is frozen; everything else may change.

Manuscript is small, explicit and value-oriented: records and enums hold data, functions hold behavior, errors and absence are values, and every value has one owner. Read [Idioms](references/idioms.md) before writing: it holds thirteen complete programs to copy. Use exact names from [Standard calls](references/standard-calls.md).

## Compile on the first build

Nearly every failed first build is an ownership slip. The model is small: **borrow by default, `move` is the only slot that owns, `.clone()` is the only copy.** Nothing copies behind your back, so the compiler tells you where an owner is missing.

1. **Pass values plainly; the signature says how they are used.** A parameter borrows its argument: reading, comparing and calling methods need nothing. A function that changes its argument declares `var p T`; a function that keeps, stores or returns its argument declares `move p T`. Call sites never write `var` or `move`: `add_gift(cart)`, `archive(cart, history)`.
2. **A value moves at its last use.** Storing it in a field, a collection or a `move` parameter takes it; after that the old name is dead ("moved here but used again"). Write `.clone()` only when you still need the original or when the value is a borrow (a loop variable, a `split` piece, an element read, a parameter that is not `move`): `out.append(word.clone())`, `Sale(parts[0].clone(), n)`. Int, Float, Bool and payload-free enums copy and never need it.
3. **A result that is part of an argument says so.** `fn hold User.name() &String => self.name` returns a borrow of the receiver; `fn first(hold xs List[T]) &T?` of the argument. `hold` marks the argument the result keeps using, `&` marks the result, written with no space (`&List[Int]`; bounds like `Hashable & Clonable` keep spaces). While such a result is alive, the owner cannot change. A result without `&` is a new value: return `.clone()` of a part. A parameter of function type takes no `move`, `hold` or `&`.
4. **Mutation is declared.** A local you change is `var`; `x := e` is immutable and cannot be assigned, appended to or have a `fn var` method called. A method that changes `self` is `fn var Type.m`; a function that changes a parameter takes `var p T`. `var y = x.part` borrows `x.part` exclusively, so changes reach `x`; `var y = x.part.clone()` is independent.
5. **Absence and failure.** `T?` is tested with `x == null` / `x != null` (an `if v := x` unwraps a Result, never an Optional), defaulted with `x or d`, turned into an error with `ok_or(x, Error("what"))?`. `T!` is `Result[T, Error]` (write the error type only when it is not `Error`: `T!MyError`); return `ok(v)` or `error(Error("what"))`; `?` unwraps or returns early.
6. **Shapes.** Every `fn` has a result type (`Void` if none); a block is never empty (no `pass`); comments are `//`; `not x`, `==`, `} else if c {`. An empty `[]` or `{}` needs a type from context: `xs List[Int] := []`, `Map[String, Int]()`.

```manuscript
fn tally(lines List[String]) Map[String, Int] {
    var counts = Map[String, Int]()

    for line in lines {
        for word in line.split(" ") {
            counts[word.clone()] = counts.get_or(word, 0) + 1
        }
    }

    return counts
}
```

`lines` and `word` are borrowed, so the key stored in `counts` is a `.clone()`; `counts` is new, so `return counts` moves it.

## Write it this way

- **Data:** a `type` for facts, an `enum` for states, `match` covering every case. Defaults and named arguments instead of builder code.
- **Transformation:** a pipeline (`xs | .filter(f) | .map(g) | .sum()`) to derive values; a `for` loop to build a Map or change a `var`. A named function beats a one-use closure.
- **Ownership:** borrow when reading, `var` when changing, `move` when storing. `.clone()` is for a real second owner and costs time and memory: borrow, move at the last use, or keep an index first.
- **Short forms:** `print(x)`, not `stdout().write`. `0..n`, `[0].repeated(n)`, `.map`, `.filter`, `.any`, `.all`, `.sum()`, `xs.extend(ys)` instead of loops that build or accumulate. `x := if c { a } else { b }`, `m.get_or(k, d)`, `xs[i]`, `s.is_empty()`, `a.max(b)`, `for _round in` for an unused name, `"""` for multi-line text.
- **Failure:** `T!` for what can fail, `return ok(v)` / `return error(Error("what"))`, `?` to propagate, and in a test `f()?` to read a Result. `T?` when absence is normal. Do not write `call().get()` as a statement (it faults on error): use `call()?` (`main` may return `Void!`), or `void call()` to ignore the outcome.
- **Waiting:** no `async`. A waiting call returns a Promise already running; start several, `wait_all` them. Streams are read with `for line in stream | lines`. Share state through one owner and a pipe.
- **Tests:** `test "name" { ... }` blocks beside the code, run by `ms test`.

## Changing existing code

Read the file, its tests and `ms.toml` first, and match the style around you. Add an enum case, then let `ms check` list every `match` that must handle it. (`--fix` does not write the arms; add them by hand.) Change a signature, then fix each call the checker reports. Keep the change small, run `ms check --fix`, `ms test`, then `ms verify`. Add a `test` for the behavior you changed.

## Syntax card

A body is a `{ ... }` block, formatted with tabs by `ms fmt`; indentation carries no meaning. A module contains imports and declarations; `main` is its entry point. Fields belong inside `type`; methods sit beside it with implicit `self`; `fn var` permits receiver mutation, `fn hold` returns a borrow of the receiver, `fn move` takes it.

<!-- complete: skill-core.ms -->
```manuscript
type Counter {
    n Int = 0
    label String = "count"
}

fn var Counter.add(value Int) Void {
    self.n += value
}

fn hold Counter.name() &String => self.label

fn Counter.value() Int => self.n

fn relabel(var counter Counter, move label String) Void {
    counter.label = label
}

fn main() Void! {
    value := ok_or("42".parse_int(), Error("expected an integer"))?
    var counter = Counter()
    counter.add(value)
    relabel(counter, "total")
    print(f"{counter.name()}: {counter.value()}")
}
```

- Bindings: `x := e` (immutable, `x T := e`), `var x = e` (mutable). Types: Int, Float, Bool, String, Void; literals `true`, `false`, `void`. A name is followed by its type with no colon: `fn f(x Int)`, `n Int := 3`, `[T Comparable]`; names of one type share it: `width, height Int`; a mode before the group covers all of it (`hold left, right T`).
- Functions: `fn f(x Int, n Int = 1) Int { ... }`, called `f(2, n: 3)`; labels are optional. A one-expression body is `=>`: `fn double(x Int) Int => x * 2`. Closures: `x => x + 1` where a callback type is known, `(a, b) => a + b`, typed `fn(n Int) Int => n * 2`; a longer body is `x => { ... }` with explicit `return`. Function types are `fn(Int) Int`. Generics: `fn id[T](x T) T`, bounds `[T Comparable]`, several `[T Hashable & Clonable]`.
- Control: `if`/`else if`/`else`, `while`, `for x in xs { ... }`, `for i in 0..n { ... }` (excludes n), `break`, `continue`, `and or not`. Early exits: `if c { return x }`. Expression form: `if c { a } else { b }`.
- Collections need no import: `[1, 2]`, `Map[String, Int]()`, `Set[Int]()`, `{"a": 1}`. `m.get(k)` is an Optional borrow; `m.get_or(k, d)` has a fallback. A List has no `get`: `xs[i]` is the element (negative counts from the end; out of range faults), `xs.get_or(i, d)` has a fallback. `xs.slice(a, b)` is a borrowed Result that is an error when `b` is past the end (no clamping); `String.slice(a, b)` is a plain String. `xs.first()`, `m.keys()`, `s.split(",")` borrow their receiver: use them in place or `.clone()` to keep them.
- Imports: `import name from "./other.ms"` and `import sqrt from "@std/math/math.ms"`; `export` shares a declaration; `ms search_symbol <name>` prints a name's import line.
- `enum Choice { ... }` with cases `Empty` and `Value(n Int)`, built `Choice.Value(2)`, matched with arms `Empty =>`, `Value(n) =>`, `_ =>`. Keep `match` flat: bind with an early exit, use `?`, or call a small helper.
- Text: `"plain"` never interpolates (braces are literal), `f"total {n}"` interpolates, `r"\d+"` is raw, `"""` and `r"""` open multi-line text on the next line.
- Effects: narrow directives above functions that reach files, the clock or the network; they do not run effects. `ms check` ignores effects; `ms verify` reports each one a function reaches (`std.fs.read`, `std.fs.write`, `std.clock.read`, `std.net...`) and the message names the exact directive to add. `print` needs none.
- Iteration over your own data: a record with a `&` field (a *look*) and `fn var next() &T?` works in `for` with no copies. There is no stdlib cursor type; write the record when you need one.
- Not in the language: no `~ & | ^ << >>` operators (`bit_and`, `bit_or`, `bit_not`, `shift_left`, `shift_right` from `@std/math/math.ms`); no `let`, no `assert` (import `expect_equal`, `expect_true` from `@std/test/test.ms`, call with `?`), no `x is Case` (use `match`), no static or constructor methods (write a free function `new_store()`), no `fn var` on a free function (use `var` on the parameter), no `export` on methods (they travel with the type), no tuples (a `type`), no references to functions (a function is not a value to borrow or move). An unused binding is an error: write `_name`. Closeable values clean up at scope end; there is no GC.

## Compiler rules

Four rules cover most compiler errors; an error that names one is that rule.

1. **One owner.** "Moved here but used again" means clone at the store, or move only at the last use. "Is a view of another value, not an owner" means the value is borrowed: `.clone()` it, or declare the parameter `move`. "Parameter is not declared var" means write `var p T` in the signature. While a binding borrows from `xs` (`it := xs[0]`, `for x in xs`), do not change `xs`.
2. **`?` unwraps a Result or an Optional.** It leaves the function on error or absence: the function must return a matching Result, or an Optional/`Void` for an Optional. `s.parse_int()` is `Int?`: `ok_or(s.parse_int(), Error("bad number"))?` in a `Result` function. A Result is never dropped; `_done := f(x)?` when its value is unused. `r?.abs()` unwraps then calls.
3. **Names are exact.** Never translate: `xs.append(x)` not `push`, `contains` not `contains_key`, `pop` not `remove_last`, `is_error` not `is_err`, `x.length()` not `x.len`, `x == null` not `x.is_none()`. An Optional needs no wrapper: `return value`, never `some(value)` (absent is `null`).
4. **Shapes are fixed.** A body is a `{ ... }` block after its header, even for one statement. `for _i in xs` (a bare `_` is no name). Records, not tuples; `List[Int]`, not `List<Int>`; `not x`, not `!x`. Reserved words (`type`, `test`, `fn`, `var` ...) are never names.

## References by task

- Start here: [Idioms](references/idioms.md) (thirteen complete programs), [Standard calls](references/standard-calls.md) (every prelude call, exact), [Standard modules](references/standard-modules.md) (which `@std` module exports which names, for imports).
- Language: [Program structure](references/program-structure.md), [Projects, ms.toml and packages](references/projects-and-packages.md), [Values and control](references/values-and-control.md), [Types and functions](references/types-and-functions.md).
- Data and failure: [Collections and pipelines](references/collections-and-pipelines.md), [Errors and optionals](references/errors-and-optionals.md), [Ownership and cleanup](references/ownership-and-cleanup.md).
- Concurrency and services: [Effects and concurrency](references/effects-and-concurrency.md), [Servers and state](references/servers-and-state.md).
- Checking: [Validation](references/validation.md) (tests, diagnostics, a wrong/right table of habits from other languages).

## Verify

Run `ms check --fix <file>` first; it applies mechanical repairs but does not format: run `ms fmt` before `ms verify`. Pass program arguments after `--`: `ms run main.ms -- in.json out.json`. Run applicable `ms check`, `ms run` and `ms test` commands after editing. `ms explain <code>` says what a diagnostic code means; `ms check --json` and `ms test --json` return the same facts as data. Check behavior, not just compilation; report unrun checks. Include imports. Prelude collections, Optional, Result, Error and print need none. For additional APIs, `ms search_symbol <words>` supplies signatures/imports; do not guess.
