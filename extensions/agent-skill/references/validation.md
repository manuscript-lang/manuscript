# Validation

After the final edit, run `ms check app.ms`, then `ms run app.ms` and verify behavior. `ms test` runs tests; `ms verify` checks projects. `--deny-warnings` rejects warnings.

Read the plain `ms check` output and apply the repairs it names; `--fix` applies machine fixes, then recheck. `--json` is for tools that parse results; it is several times larger, so agents should not use it by default. `ms explain <code>` explains diagnostics. Acceptance does not prove runtime behavior or speed.

<!-- complete-test: arithmetic.ms -->
```manuscript
import expect_equal from "@std/test/test.ms"

fn twice(value Int) Int => value * 2

test "twice" {
    expect_equal(twice(21), 42)?
}
```

Assertions return Results; `?` fails the test on error. Tests need no main. `bench "name" { ... }` introduces benchmark bodies.

Test success, failure and boundary inputs. Never expect exceptions. Avoid undeclared assignment, `try`/`await`, unwrap-style calls, `def`, enum `case`, or methods inside type bodies. Use `:=`, postfix `?`, `fn Type.method` and explicit returns instead.

For additional APIs, inspect `ms search_symbol` signatures/imports. Report compiled, executed and untested checks separately.

## Habits from other languages

- Methods always take parentheses, even with no arguments: `xs.length()`, `name.length()`, `opt == null`; `xs.length` is a method value, not an Int. Test absence with `x == null` or `x != null`. Write `not x` (no `!x`), `f(x)?` (no `try`), `fn f() Result[Int, Error] { ... }` (no `->`), `"\{ \}"` for literal braces in text, and `} else {` only after an indented `if` block.
- Inside `{}` of an `f` string, write quotes plainly: `f"{xs.join(", ")}"`, never `\"`. `r?.abs()` unwraps the Result, then calls `abs()`; it needs a Result-returning function. In a `Void!` function a bare `return` means `return ok()`; other Result functions need `ok(value)` or `error(e)`.

Each row is a shape agents wrote that fails; the right column compiles.

| Not | Write |
| --- | --- |
| `!x`, `a ?? b`, `try f()`, `x or return y` | `not x`, `a or b`, `f()?`, `if x == null { return y }` then use `x` |
| `x.len`, `x.length` | `x.length()` |
| `x.is_none()`, `x.is_some()`, `x.get_or(d)`, `x.get()`, `x.ok_or(e)` on a nullable | `x == null`, `x != null`, `x or d`, `x`, `ok_or(x, e)` |
| `if v := x { ... }` on an Optional | `if x != null { ... }`, or `v := x` then `if v != null { ... }` |
| `xs.get(i)` | `xs[i]` (faults out of range), `xs.get_or(i, d)` |
| `x := []`, `m := {}` with nothing to give the type | `xs List[Int] := []`, `Map[String, Int]()` |
| `(lo + hi) // 2` (the `//` starts a comment, so the `2` is silently dropped) | `(lo + hi) / 2`: Int `/` already truncates |
| `ys := xs.sort()`, `print(xs.reverse())` (both return nothing and change `xs` in place) | `xs.sort()` as a statement, or `ys := xs.sorted()`, `xs.reversed()` |
| `bytes.to_string()` (renders `Bytes(104, 105)`) | `ok_or(bytes.decode_utf8(), Error("not UTF-8"))?` |
| `const X = 1`, `# note`, `pass` | `X := 1`, `// note`, `void` |
| `a if c else b`, `-> T` | `if c { a } else { b }`, `fn f() T { ... }` |
| `if c { f() } else { g() }` as a statement | `if c { ... }` and `} else {` on their own lines, bodies indented |
| `fn f(out: var T)`, `fn f(a: Int)`, `x T = e` | `fn f(var out T)`, `fn f(a Int)`, `x T := e` |
| `fn f(x Int) Int: x`, `x: x + 1` bodies | `fn f(x Int) Int => x`, `x => x + 1`; every longer body is braced |
| `fn f(ref x T)`, `&x` at a call, `fn g(x &T)` | no marker: a parameter borrows; `var x T` changes, `move x T` keeps, `fn hold ... &T` returns a part |
| `fn name(u User) String { return u.name }` (a part of an argument) | `fn hold name(u User) &String` or `return u.name.clone()` |
| `T: Clonable` bound | `[T Clonable]` |
| `"total {n}"` (plain text never interpolates) | `f"total {n}"` |
| `"""text"""` on one line | `"""` ends its line; the text starts on the next line and the closing `"""` stands alone (`r"""` the same, braces literal) |
| `for _ in xs` | `for _i in xs`; a bare `_` is not a name |
| `(String, Int)`, `[A, B]` tuples | a record: `type Pair { ... }` with fields |
| `f(x)?` as a statement on a non-Void result | `_done := f(x)?` (a leading `_` marks it unused) |
| `s.parse_int()?` in a function returning `Int!` (it returns `Int?`, and `?` on an Optional needs an Optional or `Void` return) | `ok_or(s.parse_int(), Error("bad number"))?` or `s.parse_int() or 0` |
| `List<Int>`, `Map<K, V>` | `List[Int]`, `Map[K, V]` |
| `m.contains_key(k)`, `xs.remove_last()` | `m.contains(k)`, `xs.pop()` |
| `xs.sort_by(f)`, `for b in s.as_bytes()` | `xs.sort((a, b) => a.compare(b))`, `for b in values(s.as_bytes())` with `import values from "@std/bytes.ms"` |
| `set.insert(x)`, `r.is_err()`, `s.find(t)` | `set.add(x)`, `r.is_error()`, `s.index_of(t)` |

The right-hand forms of this table, in one compiling program:

<!-- complete: skill-habits.ms -->
```manuscript
import values from "@std/bytes.ms"

type Pair {
    name String
    count Int
}

fn parse_line(line String) Pair? {
    parts := line.split(" ").collect()
    if parts.length() != 2 { return null }

    count := parts[1].parse_int()
    if count == null { return null }

    return Pair(name: parts[0].clone(), count: count)
}

fn bump(var seen Set[String], move word String) Int {
    seen.add(word)
    return seen.length()
}

fn total(var counts Map[String, Int], items List[Pair]) Int {
    var sum = 0

    for pair in items {
        if counts.contains(pair.name) { sum += 1 }
        counts[pair.name.clone()] = counts.get_or(pair.name, 0) + pair.count
    }

    return sum
}

fn main() Void! {
    flag List[Bool] := []
    brace := r"{}"
    esc := "\u{1}"
    var stack = [2, 1]
    stack.sort((a, b) => a.compare(b))
    for b in values("ab".as_bytes()) {
        void b
    }
    void stack.pop()

    for _i in 0..2 {
        var seen = Set[String]()
        void bump(seen, "a")
    }

    parsed := ok_or("7".parse_int(), Error("bad number"))?
    grid List[List[Int]] := [[parsed]]
    r Int! := ok(3)
    _checked := r?
    if r.is_error() { return error(Error("bad")) }

    print(f"{brace}{esc}{flag.length()}{grid.length()}")
}
```

`ms check --fix` rewrites the file in place (it adds `.wait()` and similar repairs), and `ms fmt` may rewrite imports into a parenthesised block, so re-read the file after either. Lint errors can hide under warnings in `ms verify` output: run `ms lint` for the full list. There is no date-only type: keep `"YYYY-MM-DD"` text and validate with `parse_timestamp(f"{d}T00:00:00Z")`. Effect names you will meet: `std.console.write`, `std.fs.read`, `std.fs.write`, `std.clock.read`, `std.env.read`.

A single-file program needs no `ms.toml`: `ms verify main.ms` (bare `ms verify` wants a project; it fails on unformatted source, so run `ms fmt` first). `ms verify --deny-warnings` is the real gate: plain `ms verify` passes with lint warnings such as unused imports. `ms fmt` rewrites the file: several imports become one `import (` block listing `Name, Other from "path.ms",` entries, and a one-line `if c { ... }` body collapses to `if c { return x }`, so edit by reading the file again rather than by text substitution. Tests live in `test` blocks beside each module; the root `test.ms` from `ms init` is for cross-module checks. Compare whole strings in `expect_equal(actual, expected)?`: `expect_equal(out.contains(x), true)?` hides the output. A workspace root lists every project in `members`; a library is imported as `@geometry/lib.ms` (relative to its `source` directory). Benchmarks are `bench "name" { ... }` blocks run by `ms bench`; the body is one iteration: end it with a bare value (or a call) so the work cannot be removed, and read inputs from a fixture (`fn make_fixture() T`, read as `fixture`) so constants are not folded. A test that needs a file uses `dir := temporary("prefix")?` from `@std/os/fs.ms` and `dir.path()`.
