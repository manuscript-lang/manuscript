# Manuscript cheat sheet

Alpha: syntax/APIs may change. Indent consistently (tabs or four spaces); `//` comments.

## Write, check, run

Use inferred locals, `?`, short `|` flows and early returns. Clone only for a new owner.

Save as `total.ms`:

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
    ["12", "30"] | total? | print
```

`ms check total.ms` checks it; `ms run total.ms` prints `42`.

- Find APIs/imports: `ms search_symbol <words>` or `<module>.<Name>`. Follow signatures, not guesses. Prelude (`List Map Set Optional Result Error`) and `print` need no import.
- Repair with `ms check total.ms --json`; follow its message/fix. `ms guide <code>` explains the rule. `ms check total.ms --fix` applies fixes; recheck.
- Validate: `ms test` runs `test "name":` blocks; `ms verify` checks projects. `ms bench` runs `bench "name":` blocks. Add `--deny-warnings` to reject warnings.

## Values and syntax

- Bind: `x := e` or `x: T := e`. Mutate: `var x = e`, `n += 1`. Prefix unused names with `_`.
- Types: `Int Float Bool String Unit`; explicit numeric conversions. `"{expr}"` interpolates; `\{` and `\}` escape braces; `r"\d+"` is raw text. `unit` is the Unit value.
- Functions: `fn f(a: Int, b: Int = 1) Int:`; call `f(1, b: 2)`. Declare return types; `Unit`/`Unit!` may fall through. Inline: `fn twice(x: Int) Int: x * 2`. `main` may return an Int status.
- Generics: `fn f[T](x: T) T`. Closures: `fn x: x + 1`, or `fn(x: Int) Int: x + 1`; function type: `fn(Int) Int`.
- Control: `if`/`else if`/`else`, `while c:`, `for i in 0..n:` (excludes n), `break`, `continue`; `and or not`. Expression: `if c: a else: b`.
- A line-ending `:` needs an indented body. Inline `if c: return x` exits early; align `else` on a new line. Leading `|` or `.` continues a line.
- Imports: `import a, b from "x.ms"`; `export` shares declarations.
- Records: `type T:` with fields (`tag: String = "x"`); construct `T(a: 1)` or `T(1)`. `enum Choice:` declares `A`, `B(x: Int)`; no `case` keyword.
- Aliases: `type Rows = List[Row]`, `type Maybe[T] = T?` name the same type; they are not new types.
- Methods: `fn T.name() Unit`; `fn var` mutates self. An `interface I:` is met by a type with matching methods. `export opaque` hides fields/cases outside the file.
- Collections: `[1, 2]`, `List[T](reserve: n)`, `Map[K, V]()`, `Set[T]()`. Use `var` for `xs[i] = v`, `m[k] = v`. `xs.slice(a, b)` returns a Result. `m.get(k)` returns an Optional; `m.get_or(k, d)` supplies a default. Iterate `for e in m.entries():`; `if var n = m[k]?: n += 1` updates a present value in place.
- List methods: `xs | .filter(fn x: x > 0) | .map(fn x: x * 2) | .sum()`. `x | f(a: 1) | g? | .m()` means `(g(f(x, a: 1))?).m()`.

## Absence and errors

- `T?` is Optional: values convert, `none` is absent. Read with `if x := v:` or `v.get(default)`; `a?.b` chains absence. `?` only propagates Result errors.
- `T!` means `Result[T, Error]`; `T!E` uses your error type. Return `ok(value)` or `error(reason)`. `Error("message", kind: "EINVAL")` is a record; read `.message`.
- `r?` yields success or returns the error; the enclosing function must return a compatible Result. `if x := r:` binds success; in `else:`, `r.err()` is the error value, not Optional. Never call `.err()` on success. Never silently drop a Result.
- `match v:` handles your own types: `Case(x):`, `_:`, exhaustive. Keep match flat; use methods for Result/Optional. Optional `.map(f)` preserves Result returns as `(T!)?`; handle both layers.
- Faults (`panic`, failed `get()`) abort; they are not Results.

## Ownership and cleanup

- Strings, collections and records have one owner; enums follow their payloads. Int/Float/Bool and scalar-only enums copy. `:=` is immutable, including contents.
- `b := a`, field/index reads, non-consuming arguments, loops and match payloads borrow owned values. The owner cannot change while borrowed. `var xs = a.items` mutably borrows a collection field; scalars copy.
- Storing in a collection/record moves ownership, invalidating the old name. Use `.clone()` for another owner. Copy borrowed parts before storage: `names.append(u.name.clone())`.
- Return parts by borrow: `fn name(u: User) String: return u.name`. Clone for a new owner, including borrowed paths mixed with owned returns.
- Mutate: `fn add(var xs: List[Int]) Unit`, called `add(var xs)`. A closure mutating xs cannot go to a method of xs.
- Closeable closes at scope end unless moved. Give it `fn var T.close() Unit!`; a failed close is returned or faults.

## Effects, promises and streams

- Effects are linted: put `// ms: allow_effect std.fs.read` above the function, or pass a capability. Directives do not execute effects.
- `Promise[T]`: `p.wait()` returns `T!` once; dropping unfinished work cancels and joins. Set limits with `promise(fn: f(), options: PromiseOptions(timeout: d))`, not arguments to wait.
- Coordinate through `pipe[T](cap)`; keep mutable state with one owner. Discover imports/options with `ms search_symbol promise` or `stream`; there is no `async`/`await`.
- Stream reads return promises; `for x in s:` binds T and propagates read errors. Writes wait when full. Pipeline: `input | lines | map(f) | collect(none)`; handle the final Result.

Next: `ms search_symbol <module>`.
