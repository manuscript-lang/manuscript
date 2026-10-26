# Manuscript cheat sheet

Statically typed; native code. Four-space indentation, `#` comments. No `print`: write text via `@std/io.ms`.

<!-- complete -->
```manuscript
from "@std/io.ms" import stdout
from "@std/testing.ms" import expect_equal

def add(a: Int, b: Int) -> Int: a + b

export def main() -> Int:
    let xs = [1, 2, 3]
    let big = xs.filter(lambda x: x > 1).map(lambda x: f"{x * 2}")
    stdout().write(f"sum {add(xs[0], 2)} {big.join(",")}\n").get()
    return 0

test "addition":
    try expect_equal(add(1, 2), 3)
```

- Be terse: omit types a closure can infer, use one-line bodies (`if n < 0: return 0`; `def f(x: Int) -> Int: x * 2` returns implicitly), `xs[i]`, `xs[i] = v`, `read_lines(stdin())` (`@std/streams.ms`), and `map`/`filter`/`fold`/`join`/`get(d)` over loops. stdout flushes at exit.
- Regex: `compile` in `@std/string.ms`; `captures`, `named_captures`, `split`, `replace_template`; pattern braces need `\{`.
- Workflow: `ms search_symbol <name or words>` finds a symbol (`<module>` lists one); `ms verify` (check, fmt, lint, test); `ms review`.
- `main() -> Int` returns the exit status. `test "name":` blocks run under `ms test`: finishing passes; `error(...)` (or a failing `try`) fails.
- Imports: `from "@std/x.ms" import a, b` or `from "./local.ms" import a`; `export` shares. Prelude names (`List`, `Map`, `Set`, `Optional`, `Result`, `Error`) need no import.
- `let` binds once, `var` reassigns; `n += 1` (`-=` etc.); `for i in 0..n:` counts up, excluding `n`; steps use `range_by` from `@std/collections.ms`. Types `Int Float Bool String Unit`; `f"{expr}"` interpolates (plain `"..."` keeps braces literally); `True`/`False`; `()` is the Unit value; `a if c else b`. Function types are `Callable[[Int], Int]`; closures `lambda x: x + 1`. No implicit casts.
- `[1, 2]` List; `List[T](reserve: n)` preallocates; `Map[K, V]()`, `Set[T]()` or `Set([1, 2])` mutate in place; `for e in m.entries():` and `if var n = m.get(k): n += 1` work in place; `.clone()` is deep; storing a borrowed String needs it.
- `type T:` with fields, built `T(a: 1)` (labels optional: `T(1)`); alternatives use `case A` and `case B(x: Int)`; types are nominal.
- `Optional`: `some(x)` / `none`; unwrap with `if let x = value:` and optional `else:`, or `.get(d)`.
- `match v:` on your own types: arms `case Case(x):`, `case _:`; exhaustive. Never match `Result`/`Optional` or nest `match`; use `try`/`if let`. There are no exceptions, classes, `async`, `null`, `pass`, or `elif`-less chains: use `elif`.
- Errors: `Result[T, E]` is `ok(v)` / `error(e)`; `E` must implement `Error`; `try e` unwraps or returns the error; `if let x = result:` handles success when the error can be discarded. `.message()` reads any `Error`. Faults (`panic`, failed `get()`) abort.
- Methods: `impl T:` or `impl I for T:`, never in `type`; else `f(x)`. A `T` with `impl I for T` passes wherever `I` is expected.
- Flows: `x | f(a: 1) | try g | .m()` is `(try g(f(x, a: 1))).m()`; `| try` unwraps. Lines starting `|` or `.` continue.
- A def returning part of a parameter or the receiver writes `ref` before its result type (`def name() -> ref String`); `let x = a.b` borrows a place (shared; `var x = a.b` exclusive) without a marker.
- Closures may change captures. `with let f = try open(path):` closes `f` at block end.
- Concurrency has no async/await: `with let g = TaskGroup[T]():` (`@std/tasks.ms`), `g.spawn(lambda channel: f(x))` gives a `Task`; `t.result()` or `g.results()` waits; leaving the block cancels unfinished tasks. Timeouts are opt-in.
