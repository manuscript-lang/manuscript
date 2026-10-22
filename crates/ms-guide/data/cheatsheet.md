# Manuscript cheat sheet

Statically typed; compiled to native code. Four-space indentation, `#` comments. No `print`: write bytes via `@std/io.ms`.

<!-- complete -->
```manuscript
import stdout from "@std/io.ms"
import {expect_equal} from "@std/testing.ms"

fn add(a: Int, b: Int) Int:
    return a + b

fn say(text: String) Result[Unit, Error]:
    return stdout().write("{text}\n")

export fn main() Int:
    say("sum is {add(1, 2)}").get()
    return 0

test "addition":
    try expect_equal(add(1, 2), 3)
```

- Compact: `xs[i]`, `xs[i] = v`; one-line bodies (`if n < 0: return 0`, `fn dbl(x: Int) Int: x * 2`); closures `fn(x): x + 1` infer types; `read_lines(stdin())` in `@std/streams.ms`; stdout flushes at exit.
- Workflow: `ms search_symbol <name or words>` finds a symbol (`<module>` lists one); `ms verify` (check, fmt, lint, test); `ms review`.
- `main() Int` returns the exit status. `test "name":` blocks run under `ms test`: finishing passes; `error(...)` (or a failing `try`) fails.
- Imports: `import {a, b} from "@std/x.ms"` or `"./local.ms"`; `export` shares. Prelude names (`List`, `Map`, `Set`, `Optional`, `Result`, `Error`) need no import.
- `let` binds once, `var` reassigns; `n += 1` (also `-= *= /= %=`); `for i in range(0, n):` counts (`@std/collections.ms`). Types `Int Float Bool String Unit`; `"{expr}"` interpolates. No implicit conversion.
- `[1, 2]` List; `Map[K, V]()`, `Set[T]()` or `Set([1, 2])` mutate in place; assignment copies; `.clone()` is deep.
- `type T:` with fields, built `T(a: 1)` (labels optional: `T(1)`); alternatives use `case A` and `case B(x: Int)`; types are nominal.
- `Optional`: `some(x)` / `none`; unwrap with `if let x = value:` and optional `else:`, or `.get(d)`.
- `match v:` on your own types: arms `Case(x):`, `_:`; exhaustive. Never match `Result`/`Optional` or nest `match`; use `try`/`if let`.
- Errors: `Result[T, E]` is `ok(v)` / `error(e)`; `E` must implement `Error`; `try e` unwraps or returns the error; `if let x = result:` handles success when the error can be discarded. `.message()` reads any `Error`. Faults (`panic`, failed `get()`) abort.
- Methods: `impl T:` or `impl I for T:`, never in `type`; else `f(x)`.
- Flows: `x | f(a: 1) | try g | .m()` is `(try g(f(x, a: 1))).m()`; `| try` unwraps. Lines starting `|` or `.` continue.
- Closures may change captures. `with f = try ...:` closes `f` at block end.
- Rejected: reassigning a `let`; mixed list types; missing arguments; bare `none`; odd indentation.
