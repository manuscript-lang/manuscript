# Manuscript cheat sheet

Statically typed; native code. Four-space indentation, `#` comments. No `print`: write text via `@std/io.ms`.

<!-- complete -->
```manuscript
from "@std/io.ms" import stdout
from "@std/test.ms" import expect_equal

def add(a: Int, b: Int) -> Int: a + b

export def main() -> Int:
    let xs = [1, 2, 3]
    let big = xs.filter(lambda x: x > 1).map(lambda x: f"{x * 2}")
    stdout().write(f"sum {add(xs[0], 2)} {big.join(",")}\n").get()
    return 0

test "addition":
    try expect_equal(add(1, 2), 3)
```

- Be terse: infer closure types, one-line bodies (`def f(x: Int) -> Int: x * 2`), `map`/`filter`/`fold`/`join`/`get(d)` over loops. stdout flushes at exit.
- Workflow: `ms search_symbol <name or words>`; `ms verify` (check, fmt, lint, test); `ms review`.
- `main() -> Int` is the exit status. `test "name":` runs under `ms test`; `try fail("why")` (`@std/test.ms`) fails.
- Imports: `from "@std/x.ms" import a, b`, `from "./local.ms" import a`; `export` shares. `List Map Set Optional Result Error` need none. Bytes: `@std/bytes.ms`, `Bytes(values: [1, 2])`.
- Regex: `compile` in `@std/string.ms`; `captures`, `named_captures`, `split`, `replace_template`; pattern braces need `\{`.
- Lines: a `:` ending a line needs an indented body. `elif`, not `else if`. Lines starting `|` or `.` continue.
- Bindings: `let` once, `var` reassigns, `n += 1`. `for i in 0..n:` excludes `n`; steps: `range_by` (`@std/collections.ms`).
- Types: `Int Float Bool String Unit`, no implicit casts. `f"{expr}"` interpolates; `"..."` keeps braces. `True`/`False`, `()`.
- `if` is a statement; the expression is `a if c else b`. Closures `lambda x: x + 1`, types `Callable[[Int], Int]`.
- Collections: `[1, 2]`; `List[T](reserve: n)`; `Map[K, V]()`, `Set[T]()` mutate in place; `for e in m.entries():`, `if var n = m.get(k): n += 1`; `xs[i] = v`.
- Records: `type T:` fields, `T(a: 1)` or `T(1)`; alternatives `case A`, `case B(x: Int)`. Methods in `impl T:` / `impl I for T:`, never in `type`.
- `Optional`: `some(x)` / `none`; unwrap with `if let x = v:` (+ `else:`) or `.get(d)`.
- `match v:` only on your own types: `case Case(x):`, `case _:`, exhaustive. Never match `Result`/`Optional` or nest `match`.
- Errors: `Result[T, E]` is `ok(v)` / `error(e)`, `E` implements `Error`; `try e` unwraps or returns the error; `if let x = r:` drops the error; `.message()`. Faults (`panic`, failed `get()`) abort.
- Flows: `x | f(a: 1) | try g | .m()` is `(try g(f(x, a: 1))).m()`.
- Moves: a value moves at its last use. Moving out of an index, field, loop variable or borrow fails: use `.clone()` (deep; not on `Int`, `Float`, `Bool`, which copy).
- Borrows: `let x = a.b` / `xs[i]` borrows with no marker (`var x = a.b` exclusively); don't change `a` (`self.xs.append(..)`) before `x`'s last use: use `x` first or `.clone()`.
- A def returning part of a parameter or receiver writes `ref` before the result type (`-> ref String`); its result borrows from every argument. Otherwise return `.clone()`.
- `var` parameters need `var` at the signature and every call: `def f(var xs: List[Int])`, `f(var xs)`. A closure changing `xs` can't be passed to a method of `xs`.
- Lints (`ms lint`, `ms verify`): redundant `some(x)`, `Optional.get()` without default, unread bindings (prefix `_`).
- `with let f = try open(path):` closes `f` at block end.
- Concurrency: `with let g = TaskGroup[T]():` (`@std/tasks.ms`), `g.spawn(lambda channel: f(x))` gives a `Task`; `t.result()` / `g.results()` waits; leaving the block cancels the rest.
- No exceptions, classes, `async`, `null`, `pass`.
