# Manuscript cheat sheet

Four-space indent, `//` comments. `print(x)` is for quick output.

<!-- complete -->
```manuscript
import open from "@std/os/fs.ms"
import stdout from "@std/io/io.ms"

type Doc:
    lines: List[String]

impl Doc:
    fn longest() String:
        var best = 0
        for i in 0..self.lines.length():
            if self.lines[i].length() > self.lines[best].length(): best = i
        return self.lines[best]

fn load(path: String) Result[Doc, Error]:
    let f = try open(path)
    let lines = try f.read_lines(max_lines: 1000) // Int passes as Int?
    return ok(Doc(lines)) // moves lines

export fn main() Int:
    if let doc = load("notes.txt"):
        let top = doc.longest() // borrows doc
        let keep = top.clone() // copy
        let long = doc.lines.filter(fn l: l.length() > 3)
        print("{keep} {long.length()}")
    return 0
```

- Commands: `ms search_symbol <words>`; `ms verify` (check, fmt, lint, test); `ms review`.
- Effects: pure unless `// ms: allow_effect std.fs.*`.
- Be terse: infer closure types, one-line bodies (`fn f(x: Int) Int: x * 2`), `map`/`filter`/`fold`/`join`/`get(d)` over loops.
- `main() Int` returns the exit status. `test "name":` runs under `ms test` (`try fail("why")`, `@std/test/test.ms`), `bench "name":` under `ms bench`.
- Stdlib, imported as `@std/<dir>/<m>.ms`: `io/io` `io/streams` (`stdin() | lines`) `os/fs` `os/process` `string` `time` (regex `compile`) `bytes` `crypto` `collections/collections` `math/math` `math/decimal` `data/json` `data/csv` `data/toml` `data/yaml` `net/http` `concurrency/promise`.
- Imports: `import a, b from "@std/x.ms"`, `import a from "./local.ms"`; `export` shares. `List Map Set Optional Result Error` need none.
- Lines: a `:` ending a line needs an indented body; `else if` chains; `else` needs a block `if`, not `if c: x`; lines starting `|` or `.` continue.
- Bindings: `let` once, `var` reassigns, `n += 1`; destructure `let [a, b] = xs`, `let {name} = rec`. `and or not`, not `&& || !`.
- Types: `Int Float Bool String Unit`, no implicit casts. `"{expr}"` interpolates; write `\{` and `\}` for literal braces. `unit`.
- Control: `if`/`else if`/`else`, `while c:`, `for i in 0..n:` (excludes `n`; steps `range_by`, `@std/collections/collections.ms`), `break`, `continue`. `if` is a statement; the expression is `if c: a else: b`.
- Functions: `fn f(a: Int, b: Int = 1) Int:` (no `->`; `Unit` if none), called `f(1, b: 2)`; generics `fn f[T](x: T) T`; closures `fn x: x + 1`, typed `fn(x: Int) Int: x + 1`; types `fn(Int) Int`.
- Collections: `[1, 2]`, `xs[i] = v`, `List[T](reserve: n)`, `xs.slice(a, b)` is a `Result`; `Map[K, V]()` (`m[k] = v`, `m.add(k, v)`, `m.get(k)` is optional), `Set[T]()` mutate in place; `for e in m.entries():`, `if var n = m.get(k): n += 1`; `contains`, `split`.
- Records: `type T:` fields (`tag: String = "x"`), `T(a: 1)` or `T(1)`; `enum Choice:` variants `A`, `B(x: Int)`; no `case` keyword. Methods in `impl T:` (`var fn` mutates `self`); `interface I:` contracts, `impl I for T:` conversions.
- `T?` (Optional): values convert (no `some`); `none` is absent; unwrap with `if let x = v:` or `.get(d)`; `a?.b`.
- `match v:` only on your own types: `Case(x):`, `_:`, exhaustive. Never match `Result`/`Optional` or nest `match`.
- Errors: `T!E` (`Result[T, E]`) is `ok(v)` / `error(e)`; E needs no interface. Bare `T!` selects `Error`, whose implementations have `.message()`. `try r` gives the value or returns a compatible error; `if let x = r:` handles success.
- Faults (`panic`, failed `get()`) abort, not a `Result`.
- Flows: `x | f(a: 1) | try g | .m()` is `(try g(f(x, a: 1))).m()`.
- Ownership: every `String`, list, map, record and enum has one owner: a variable, field or element. `Int`, `Float`, `Bool` copy freely (no `.clone()`). `let` is immutable including contents: `let xs = [1]; xs.append(2)` fails, write `var xs`.
- Borrow: `let b = a`, `let x = a.b`, `xs[i]`, arguments, loop variables and match payloads read the owner's value in place; while `b` is used, `a` cannot change. `var x = a.b` changes `a.b` through `x`.
- Move: storing a value (`xs.append(s)`, a field, a list) gives it a new owner and kills the old name, so `xs.append(s.clone())` unless it is the last use. A borrowed part cannot be stored: `names.append(u.name.clone())`.
- A fn returning part of a parameter or receiver returns a borrow, no `.clone()`: `fn name(u: User) String: return u.name`; the caller reads it in place, `.clone()` to keep it. A sibling path returning a new value needs `.clone()` on the borrowed path.
- `export opaque type T:` hides fields; `export opaque enum T:` hides cases outside the file.
- `var` parameter: `fn add(var xs: List[Int])`, called `add(var xs)`. A closure changing `xs` can't be passed to a method of `xs`.
- Lints fail only on errors (`--deny-warnings`: warnings too). Unread bindings fail check (prefix `_`).
- `Closeable` (files, `impl Closeable for T:` with `var fn close() Unit!`) closes at scope end unless moved; a failed close is returned or faults.
- Waiting: `read`, `fetch`, `sleep` return a `Promise[T]`; `p.wait()` gives `T!`. Limits: `promise(fn: f(), options: PromiseOptions(timeout: d, cancel: stop.signal()))` or `p.with(options: ...)`; `stop = cancel_switch()`; `stop.cancel()`, `p.cancel()` act at the next wait. `wait_all(ps)`, `wait_first(ps)`. Dropping cancels. Share state via one owner and `pipe[T](cap)`.
- Streams: `for x in s:` binds `T`, a failed read leaves with its error; `w.write(v)` waits when full; steps `input | lines | map(f) | collect(none)`. `serve(":8080", h)` uses every core; `server.wait()`.
- Not Python: no exceptions, classes, `async`, `null`, `pass`; `fn` not `def`/`lambda`, `true`/`false`, `else if`, `none`, no `f""`.
