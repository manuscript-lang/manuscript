# Manuscript cheat sheet

Alpha: syntax/APIs may change. Indent one tab per level (four spaces also parse); `//` comments.

## Write, check, run

Save as `total.ms`. No setup needed.

<!-- complete -->
```manuscript
fn total(texts: List[String]) Int!:
    var sum = 0
    for text in texts:
        n := text.parse_int().ok_or(Error("not an integer: {text}"))?
        sum += n
    return ok(sum)

// ms: allow_effect std.console.write
fn main() Unit!:
    values := ["12", "30"]
    answer := total(values)?
    print(answer)
```

`ms check total.ms` checks it; `ms run total.ms` prints `42`.

- Discover: `ms search_symbol <words>`, then `<module>.<Name>` for signatures. Prelude (`List Map Set Optional Result Error`) and `print` need no import.
- Repair: `ms check total.ms --json` gives locations/codes/fixes; `ms guide <code>` explains the rule family. Use the diagnostic's own message/fix. `ms check total.ms --fix` applies fixes; recheck afterwards.
- Validate: `ms test` runs `test "name":` blocks; `ms bench` runs `bench "name":` blocks. `ms verify` checks the project; `ms review` explains changes. `--deny-warnings` fails on warnings.

## Values and syntax

- Bind: `x := e` or `x: T = e`. Mutate: `var x = e`, `n += 1`. Prefix intentionally unused names with `_`.
- Types: `Int Float Bool String Unit`; no implicit numeric casts. `"{expr}"` interpolates; `\{` and `\}` escape braces; `r"\d+"` and `r"""` are raw strings. `unit` is the Unit value.
- Functions: `fn f(a: Int, b: Int = 1) Int:`; call `f(1, b: 2)`. No `->`; omitted return type is Unit. `Unit`/`Unit!` need no final return. `main` may return an Int status.
- Generics: `fn f[T](x: T) T`. Closures: `fn x: x + 1`, or `fn(x: Int) Int: x + 1`; function type: `fn(Int) Int`.
- Control: `if`/`else if`/`else`, `while c:`, `for i in 0..n:` (excludes n), `break`, `continue`; `and or not`. Expression: `if c: a else: b`.
- A line-ending `:` needs an indented body. Inline `if c: return x` exits early; an `else` requires a block `if`. Leading `|` or `.` continues a line.
- Imports: `import a, b from "x.ms"`, or `import (a from "x.ms", b from "y.ms")`; `export` shares declarations.
- Records: `type T:` with fields (`tag: String = "x"`); construct `T(a: 1)` or `T(1)`. `enum Choice:` declares `A`, `B(x: Int)`; no `case` keyword.
- Methods: `fn T.name()`; `fn var` mutates self. An `interface I:` is met by matching methods or `impl I for T:`. `export opaque type T:` or `export opaque enum T:` hides fields/cases outside the file.
- Collections: `[1, 2]`, `List[T](reserve: n)`, `Map[K, V]()`, `Set[T]()`. Mutation needs `var`; `xs[i] = v`, `m[k] = v`. `xs.slice(a, b)` returns a Result. `m.get(k)` returns an Optional; `m.get_or(k, d)` supplies a default. `for e in m.entries():` visits entries; `if var n = m[k]?: n += 1` updates a present value in place.
- Use collection operations (`any all count sum map filter fold`) where useful. Pipe `x | f(a: 1) | g? | .m()` means `(g(f(x, a: 1))?).m()`.

## Absence and errors

- `T?` is Optional: values convert, `none` is absent. Read with `if x := v:` or `v.get(default)`; `a?.b` chains absence. `?` only propagates Result errors.
- `T!` means `Result[T, Error]`; `T!E` uses your error type. Return `ok(value)` or `error(reason)`. Error is a record: `Error("message", kind: "EINVAL")`; read `.message`, not `.message()`.
- `r?` gives the success value or returns the error from the function with matching error type. `if x := r:` handles success only; use `r.is_error()` and `r.err()` for failure. Never silently drop a Result.
- `match v:` handles your own types: `Case(x):`, `_:`, exhaustive. Keep match flat; use methods for Result/Optional. Optional `.map(f)` with a Result-returning f discards its error: handle it explicitly if needed.
- Faults (`panic`, failed `get()`) abort; they are not Results.

## Ownership and cleanup

- Strings, collections, records and enums each have one owner. Int/Float/Bool copy freely. `:=` is immutable including contents: `xs := [1]; xs.append(2)` fails; use `var xs`.
- `b := a`, field/index reads, arguments, loop variables and match payloads borrow in place. While the borrow is used, the owner cannot change. `var x = a.b` mutably borrows that field.
- Storing (`xs.append(s)`, a record field, a list element) moves ownership; invalidating the old name. Use `.clone()` for another owner. A borrowed part needs a copy before storage: `names.append(u.name.clone())`.
- Returning part of a parameter/receiver returns a borrow: `fn name(u: User) String: return u.name`. Clone for a separate value. If another path constructs a value, clone the borrowed path too.
- Mutate: `fn add(var xs: List[Int])`, called `add(var xs)`. A closure mutating xs cannot go to a method of xs.
- Closeable closes at scope end unless moved. Use `impl Closeable for T:` or `fn var T.close() Unit!`; a failed close is returned or faults.

## Effects, promises and streams

- Effects are linted; permit operations above the function: `// ms: allow_effect std.fs.read`, or pass a capability. Permissions document, not execute, effects.
- Promise[T] owns one pending result: `p.wait()` returns `T!` and takes it once. Dropping unfinished work cancels and joins. Limits use `promise(fn: f(), options: PromiseOptions(timeout: d))` or `p.with(options: ...)`, not arguments to wait.
- `stop := cancel_switch()` gives `stop.signal()` for options; `stop.cancel()` or `p.cancel()` cancels at a wait. `wait_all(ps)`, `wait_first(ps)` combine results. Share mutable state through one owner and `pipe[T](cap)`.
- Stream reads return promises; `for x in s:` binds T and propagates read errors. Writes wait when full. Pipeline: `input | lines | map(f) | collect(none)`; handle the final Result.

Next: `ms search_symbol <module>` for APIs; `ms guide <code>` for diagnostics.
