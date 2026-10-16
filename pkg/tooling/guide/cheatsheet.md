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
    match say("sum is {add(1, 2)}"):
        ok(_): return 0
        error(_): return 1

test "addition":
    expect_equal(add(1, 2), 3)
```

- Workflow: `ms search_symbol <name or words>` finds a project or std symbol (`ms search_symbol <module>` lists a module); `ms check`, `ms fmt`, `ms test` after each edit.
- `main() -> Int` returns the exit status. `test "name":` blocks run under `ms test`.
- Imports: `import {a, b} from "@std/x.ms"` or `"./local.ms"`; `export` shares. Prelude names (`List`, `Map`, `Set`, `Optional`, `Result`, `Error`) need no import.
- `let` binds once, `var` reassigns. Types `Int Float Bool String Unit`; `"{expr}"` interpolates. No implicit conversion or truthiness.
- `[1, 2]` List; `Map[K, V]()`, `Set[T]()` mutate in place; assignment shares, `.clone()` is shallow.
- `type T:` with fields, built `T(a: 1)`; alternatives use `case A` and `case B(x: Int)`; types are nominal.
- `Optional`: `some(x)` / `none`; read with `match`, `.unwrap_or(d)`.
- `match v:` arms `Case(x):`, `_:`; exhaustive. Keep it flat: never nest `match`; early-return, `try`, or a helper.
- Errors: `Result[T, E]` is `ok(v)` / `error(e)`; `try e` unwraps or returns the error. `Error` is the common boundary (`.message()`). Faults (`panic`, `unwrap()` on `none`) abort.
- Methods only via `interface I:` + `impl I for T:` (no `impl T:`); other functions are `f(x)`.
- Closures snapshot bindings; shared collections stay shared. `with f = try ...:` closes `f` at block end.
- Common rejects: reassigning a `let`; mixed list types; missing arguments; bare `none` without type context; indentation not a multiple of four.
