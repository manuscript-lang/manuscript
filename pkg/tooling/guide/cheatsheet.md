# Manuscript cheat sheet

Statically typed; compiled to Go. Four-space indentation, `#` comments. No `print`: write bytes via `@std/io.ms`.

<!-- complete -->
```manuscript
import stdout from "@std/io.ms"
import {expect_equal} from "@std/testing.ms"

fn add(a: Int, b: Int) -> Int:
    return a + b

fn say(text: String) -> Result[Unit, Error]:
    try stdout().write("{text}\n".to_bytes())
    return stdout().flush()

export fn main() -> Int:
    say("sum is {add(1, 2)}").unwrap()
    return 0

test "addition":
    try expect_equal(add(1, 2), 3)
```

- Workflow: `ms search_symbol <name or words>` finds a project or std symbol (`ms search_symbol <module>` lists a module); `ms verify` (check, fmt, lint, test) after each edit; `ms review`/`ms diagram` map changes.
- `main() -> Int` returns the exit status. `test "name":` blocks run under `ms test`: finishing passes, returning `error(...)` (or `try` on a failing check) fails.
- Imports: `import {a, b} from "@std/x.ms"` or `"./local.ms"`; `export` shares. Prelude names (`List`, `Map`, `Set`, `Optional`, `Result`, `Error`) need no import.
- `let` binds once, `var` reassigns; `n += 1` (also `-= *= /= %=`); `for i in range(0, n):` counts (`@std/collections.ms`). Types `Int Float Bool String Unit`; `"{expr}"` interpolates. No implicit conversion or truthiness.
- `[1, 2]` List; `Map[K, V]()`, `Set[T]()` mutate in place; assignment shares, `.clone()` is shallow.
- `type T:` with fields, built `T(a: 1)` (labels optional: `T(1)`); alternatives use `case A` and `case B(x: Int)`; types are nominal.
- `Optional`: `some(x)` / `none`; unwrap with `if let x = value:` and optional `else:`, or `.unwrap_or(d)`.
- `match v:` on your own types: arms `Case(x):`, `_:`; exhaustive. Never match `Result`/`Optional` or nest `match`; use `try`/`if let`.
- Errors: `Result[T, E]` is `ok(v)` / `error(e)`; `try e` unwraps or returns the error; `if let x = result:` handles success when the error can be discarded. `Error` is the common boundary (`.message()`). Faults (`panic`, failed `unwrap()`) abort.
- Methods only via `interface I:` + `impl I for T:` (no `impl T:`); other functions are `f(x)`.
- Flows: `x | f(a: 1) | try g | .m()` is `(try g(f(x, a: 1))).m()`; `| try` unwraps. Lines starting `|` or `.` continue.
- Closures snapshot bindings. `with f = try ...:` closes `f` at block end.
- Common rejects: reassigning a `let`; mixed list types; missing arguments; bare `none` without type context; odd indentation.
