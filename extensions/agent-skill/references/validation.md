# Validation

After the final edit, run `ms check app.ms`, then `ms run app.ms` and verify behavior. `ms test` runs tests; `ms verify` checks projects. `--deny-warnings` rejects warnings.

`ms check app.ms --json` gives structured diagnostics. Apply indicated repairs; `--fix` applies machine fixes, then recheck. `ms explain <code>` explains diagnostics. Acceptance does not prove runtime behavior or speed.

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
| `!x`, `a ?? b`, `try f()`, `x or return y` | `not x`, `a or b`, `f()?`, `if v := x { ... }` then use `v` |
| `x.len`, `x.length` | `x.length()` |
| `x.is_none()`, `x.is_some()`, `x.get_or(d)` on a nullable | `x == null`, `x != null`, `x or d` |
| `(lo + hi) // 2` (the `//` starts a comment, so the `2` is silently dropped) | `(lo + hi) / 2`: Int `/` already truncates |
| `ys := xs.sort()`, `print(xs.reverse())` (both return nothing and change `xs` in place) | `xs.sort()` as a statement, or `ys := xs.sorted()`, `xs.reversed()` |
| `bytes.to_string()` (renders `Bytes(104, 105)`) | `bytes.decode_utf8().ok_or(Error("not UTF-8"))?` |
| `const X = 1`, `# note`, `pass` | `X := 1`, `// note`, `void` |
| `a if c else b`, `-> T` | `if c { a } else { b }`, `fn f() T { ... }` |
| `if c { f() } else { g() }` as a statement | `if c { ... }` and `} else {` on their own lines, bodies indented |
| `fn f(out: var T)`, `x T = e` | `fn f(var out T)`, `x T := e` |
| `"total {n}"` (plain text never interpolates) | `f"total {n}"` |
| `"""text"""` on one line | `"""` ends its line; the text starts on the next line and the closing `"""` stands alone (`r"""` the same, braces literal) |
| `for _ in xs` | `for _i in xs`; a bare `_` is not a name |
| `(String, Int)`, `[A, B]` tuples | a record: `type Pair { ... }` with fields |
| `f(x)?` as a statement on a non-Void result | `_done := f(x)?` (a leading `_` marks it unused) |
| `s.parse_int()?` in a function returning `Int!` (it returns `Int?`, and `?` on an Optional needs an Optional or `Void` return) | `s.parse_int().ok_or(Error("bad number"))?` or `s.parse_int().get_or(0)` |
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
    parts := line.split(" ")
    if parts.length() != 2 { return null }

    n := parts.get_or(1, "").parse_int()
    if count := n {
        return Pair(name: parts.get_or(0, ""), count: count)
    }

    return null
}

fn bump(var seen Set[String], word String) Int {
    seen.add(word)
    return seen.length()
}

fn total(var counts Map[String, Int], items List[Pair]) Int {
    var sum = 0

    for pair in items {
        if counts.contains(pair.name.clone()) { sum += 1 }
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

    parsed := "7".parse_int().ok_or(Error("bad number"))?
    grid List[List[Int]] := [[parsed]]
    r Int! := ok(3)
    _checked := r?
    if r.is_error() { return error(Error("bad")) }

    print(f"{brace}{esc}{flag.length()}{grid.length()}")
}
```

`ms check --fix` rewrites the file in place (it adds `.wait()` and similar repairs), and `ms fmt` may rewrite imports into a parenthesised block, so re-read the file after either. Lint errors can hide under warnings in `ms verify` output: run `ms lint` for the full list. There is no date-only type: keep `"YYYY-MM-DD"` text and validate with `parse_timestamp(f"{d}T00:00:00Z")`. Effect names you will meet: `std.console.write`, `std.fs.read`, `std.fs.write`, `std.clock.read`, `std.env.read`.

A single-file program needs no `ms.toml`: `ms verify main.ms` (bare `ms verify` wants a project). `ms verify --deny-warnings` is the real gate: plain `ms verify` passes with lint warnings such as unused imports. `ms fmt` rewrites the file: several imports become one `import (` block listing `Name, Other from "path.ms",` entries, and a one-line `if c { ... }` body collapses to `if c { return x }`, so edit by reading the file again rather than by text substitution. Tests live in `test` blocks beside each module; the root `test.ms` from `ms init` is for cross-module checks. Compare whole strings in `expect_equal(actual, expected)?`: `expect_equal(out.contains(x), true)?` hides the output. A workspace root lists every project in `members`; a library is imported as `@geometry/lib.ms` (relative to its `source` directory). Benchmarks are `bench "name" { ... }` blocks run by `ms bench`; use `void f(x)` for an unused result and `keep` from `@std/test/bench.ms` so the call is not optimised away. A test that needs a file uses `dir := temporary("prefix")?` from `@std/os/fs.ms` and `dir.path()`.
