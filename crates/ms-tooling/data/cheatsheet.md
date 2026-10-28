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

- Helpful commands: `ms search_symbol <name or words>`; `ms verify` (check, fmt, lint, test); `ms review`.
- Be terse: infer closure types, one-line bodies (`def f(x: Int) -> Int: x * 2`), `map`/`filter`/`fold`/`join`/`get(d)` over loops.
- `main() -> Int` is the exit status. `test "name":` runs under `ms test` (`try fail("why")`, `@std/test.ms`); `bench "name":` under `ms bench`. stdout flushes at exit.
- Stdlib (`@std/<m>.ms`): `io` `fs` `streams` (`read_lines(stdin())`) `string` (regex `compile`; braces need `\{`) `collections` `bytes` `decimal` `json` `csv` `toml` `yaml` `time` `math` `random` `crypto` `process` `http` `net` `tasks` `channels` `workers` `sync` `shared`.
- Imports: `from "@std/x.ms" import a, b`, `from "./local.ms" import a`; `export` shares. `List Map Set Optional Result Error` need none.
- Lines: a `:` ending a line needs an indented body; `elif`, not `else if`; lines starting `|` or `.` continue. Module constants: `let LIMIT = 3`.
- Bindings: `let` once, `var` reassigns, `n += 1`; destructure `let [a, b] = xs`, `let {name} = rec`. Operators `and or not`.
- Types: `Int Float Bool String Unit`, no implicit casts. `f"{expr}"` interpolates; `"..."` keeps braces. `True`/`False`, `()`.
- Control: `if`/`elif`/`else`, `while c:`, `for i in 0..n:` (excludes `n`; steps `range_by`, `@std/collections.ms`), `break`, `continue`. `if` is a statement; the expression is `a if c else b`.
- Functions: `def f(a: Int, b: Int = 1) -> Int:`, called `f(1, b: 2)`; generics `def f[T](x: T)`; closures `lambda x: x + 1`; types `Callable[[Int], Int]`.
- Collections: `[1, 2]`, `xs[i] = v`, `List[T](reserve: n)`, `xs.slice(a, b)` is a `Result`; `Map[K, V]()`, `Set[T]()` mutate in place; `for e in m.entries():`, `if var n = m.get(k): n += 1`; `contains`, `split`.
- Records: `type T:` fields (`tag: String = "x"`), `T(a: 1)` or `T(1)`; alternatives `case A`, `case B(x: Int)`. Methods in `impl T:` (`var def` mutates `self`), never in `type`; `interface I:` with `impl I for T:`, and a `T` passes where `I` is expected.
- `Optional`: `some(x)` / `none`; unwrap with `if let x = v:` (+ `else:`) or `.get(d)`.
- `match v:` only on your own types: `case Case(x):`, `case _:`, exhaustive. Never match `Result`/`Optional` or nest `match`.
- Errors: `Result[T, E]` is `ok(v)` / `error(e)`, `E` implements `Error`; `try e` unwraps or returns the error; `if let x = r:` drops the error; `.message()`. Faults (`panic`, failed `get()`) abort. Flows: `x | f(a: 1) | try g | .m()` is `(try g(f(x, a: 1))).m()`.
- Moves: a value moves at its last use. Moving out of an index, field, loop variable or borrow fails: use `.clone()` (deep; not on `Int`, `Float`, `Bool`, which copy).
- Borrows: `let x = a.b` / `xs[i]` borrows with no marker (`var x = a.b` exclusively); don't change `a` (`self.xs.append(..)`) before `x`'s last use: use `x` first or `.clone()`.
- A def returning part of a parameter or receiver writes `ref` before the result type (`-> ref String`); its result borrows from every argument. Otherwise return `.clone()`.
- `var` parameters need `var` at the signature and every call: `def f(var xs: List[Int])`, `f(var xs)`. A closure changing `xs` can't be passed to a method of `xs`.
- Lints (`ms lint`, `ms verify`): redundant `some(x)`, `Optional.get()` without default, unread bindings (prefix `_`).
- Cleanup: `with let f = try filesystem().open(path, flags: "r", mode: 0):` (`@std/fs.ms`) closes `f` at block end. Concurrency: `with let g = TaskGroup[T]():`, `g.spawn(lambda channel: f(x))` gives a `Task`; `t.result()` / `g.results()` waits; leaving the block cancels the rest.
- No exceptions, classes, `async`, `null`, `pass`.
