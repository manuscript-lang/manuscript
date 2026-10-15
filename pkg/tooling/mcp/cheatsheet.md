# Manuscript cheat sheet

Manuscript is statically typed. `.ms` source is checked, then lowered to Go and built natively. Blocks are defined by indentation (four spaces); `#` starts a comment. There is no `print`: write bytes through `@std/io.ms`.

## Workflow

1. `std_lookup` any standard API before using it. Never guess a signature.
2. Edit, then `check` (JSON diagnostics; each message reads `<cause>; <fix>`). Fix every diagnostic.
3. `fmt` for canonical layout, `lint` for hygiene, `test` and `run` on the project's `ms.toml`.

## Programs and tests

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

- `export fn main() -> Int` is the entry point; the return value is the exit status.
- `test "name":` blocks run under `ms test`; `panic` from `@std/faults.ms` or helpers from `@std/testing.ms` fail them. A tests file needs no `main`.
- Imports go at the top: `import name from "@std/io.ms"`, `import {a, b} from "./local.ms"`. Standard modules are `@std/<name>.ms`; only the prelude (`List`, `Map`, `Set`, `Optional`, `Result`, `Error`, ...) needs no import, and importing a prelude name is rejected.
- Export what other files need with `export`.

## Values and types

- `let` binds once; `var` allows reassignment. Types are inferred locally; annotate with `let x: Int = 1`.
- Primitives: `Int`, `Float`, `Bool`, `String`, `Unit`. Interpolate with `"{expression}"`.
- No implicit numeric conversion, implicit unwrapping, or truthiness: conditions must be `Bool`.
- Collections: `[1, 2]` is a `List`; `Map[String, Int]()` and `Set[String]()` are built with constructors and mutated with `.add`, `.append`. Assignment shares; `.clone()` is shallow. List elements need one type.
- Records: `type Todo:` with `title: String` fields; build with `Todo(title: "x", completed: false)`. Fields are mutable even through `let`. Types are nominal.
- Alternatives: `type Status:` with `case Draft` and `case Published(url: String)`.
- Optional: `some(x)` or `none`, from the prelude. Lookups such as `map.get(key)` return it. Use `match`, `.is_none`, `.unwrap_or(fallback)`. No implicit unwrapping.

## Control flow

- `if` / `else`, `while`, `for item in items:`, `break`, `continue`.
- `match value:` arms are `Case(payload): ...` or `_:`; matches must be exhaustive and every reachable arm must return where the function returns.
- Keep `match` flat: never nest one inside another arm. Bind the payload with an early return, use `try`, or call a helper function.

## Functions and closures

- `fn name(a: Int, b: String) -> Int:`; no result is `-> Unit`. Call positionally or with labels: `line_total(price: 12, quantity: 3)`.
- Function values: `fn(value: Int) -> Int:` with an indented body, passed to `map(transform: ...)`, `filter(predicate: ...)`.
- A closure snapshots each captured binding when created. Reassigning a `var` later does not change the snapshot; captured lists and records are shared, so mutations are visible.
- User methods go through interfaces: `interface Name:` declares operations, `impl Name for Type:` implements them with `self`. There are no inherent methods (`impl Type:` is rejected); a free function is called `f(x)`, not `x.f()`.

## Errors

- Expected failures are `Result[T, E]`: `ok(value)` or `error(cause)`. `try expr` unwraps `ok` or returns the error to the caller; the caller's error type must match or be `Error`.
- `Error` is the common boundary; call `cause.message()`.
- Programming faults (`panic`, `unwrap()` on `none`) end the test or program; they are not ordinary values.

## Resources

`with file = try filesystem().open(path: "notes.txt", flags: "r", mode: 0):` closes the resource when the block ends, including on early return. A closure that captures it does not keep it open.

## Common rejections

- `let count = 2` then `count = 3`: use `var`.
- `[1, "two"]`: elements need a common type.
- Missing arguments or labels: supply every required argument.
- `none` with no expected type: annotate or qualify (`Optional[String].none`).
- Indentation that is not a multiple of four spaces.
