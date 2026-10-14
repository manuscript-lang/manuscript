# Manuscript cheat sheet (for command-line programs that read stdin and write stdout)

Written against the compiler pinned in the benchmark. Build: `ms lock ms.toml && ms build ms.toml -o prog`. `ms check ms.toml` type-checks only.
Fuller docs: `ms help`, and `ms stdlib <dir>` writes the standard declarations (`string.ms`, `collections.ms`, ...). Indentation (4 spaces) defines blocks, `#` starts a comment.

## Skeleton

```manuscript
import {stdin, stdout, read_line, read_all} from "@std/io.ms"

fn run() -> Result[Unit, Error]:
    while true:
        let next = try read_line(input: stdin(), max_bytes: 1048576)   # Optional[String]; none at EOF
        if next.is_none():
            break
        let line = next.unwrap()                                       # no line terminator
        try stdout().write("{line}\n".to_bytes())
    return stdout().flush()

export fn main() -> Int:
    match run():
        ok(_): return 0
        error(_): return 1
```

- Whole input: `let data = try read_all(input: stdin())` gives `Bytes`; `data.to_text()` is `Optional[String]`; `data.values()` is `List[Int]` of bytes.
- `try expr` unwraps `ok`/`some`-style success or returns the error. As a bare statement the success type must be `Unit` (use `let _x = try ...` otherwise).
- Match arms cannot hold a bare `try` statement or `continue` as a value; move the work to a helper function or use `if r.is_error(): continue`.

## Names and syntax traps

- Reserved words, not usable as names: `from`, `unit`, `_`, `type`, `fn`, `let`, `var`, `match`, `case`, `impl`, `try`, `with`.
- Top level holds only imports, `fn`, `type`, `interface`, `impl`, `test`: no top-level `let`. Use a zero-argument `fn` for constants.
- `{expr}` inside a string interpolates. A literal brace is `\{` or `\}`. Escapes: `\n`, `\t`, `\r`, `\"`.
- `let` binds once, `var` can be reassigned. Types are inferred; annotate with `let x: Int = 3`.
- Calls take positional or labeled arguments: `m.add(key: "a", value: 1)`. Callback parameters for `sorted` must be named `left` and `right`.
- `and`, `or`, `not` are the boolean operators. `/` on `Int` truncates toward zero, `%` is the remainder. Int arithmetic is checked and faults on overflow.
- No tuples, no nested patterns, no methods on your own types: write free functions that take the record.
- `else if` works. There is no `continue` inside `match` arms.

## Records and alternatives

```manuscript
type Point:
    x: Int
    y: Int

type Shape:
    case Circle(radius: Int)
    case Square(side: Int)
    case Empty

fn area(s: Shape) -> Int:
    match s:
        Circle(radius): return radius * radius * 3
        Square(side): return side * side
        Empty: return 0

let p = Point(x: 1, y: 2)       # inside a function body
p.x = 5                          # records are mutable and shared by reference; p.clone() copies
```

`Optional[T]` is `some(v)` or `none`; `Result[T, E]` is `ok(v)` or `error(e)`:
`o.is_some()`, `o.is_none()`, `o.unwrap()`, `o.unwrap_or(default)`, `r.is_error()`.
Build them with `return some(v)`, `return none`, `return ok(v)`, `return error("msg")`. A function returning `Result[Int, String]` can use `let v = try other()` where `other` has the same error type.

## Collections (List, Map, Set are built in; Set needs `import Set from "@std/collections.ms"`)

```manuscript
import MapEntry from "@std/collections.ms"

let xs = List[Int]()             # also [1, 2, 3]
xs.append(4)                     # mutates
xs.at(0)                         # Optional[Int]; xs.length(); xs.set(i, v); xs.remove(i)
xs.first(); xs.last(); xs.contains(3); xs.join(",") only for List[String]
let sorted_xs = xs.sorted(compare: fn(left: Int, right: Int) -> Int:
    return left - right
)
let doubled = xs.map(transform: fn(value: Int) -> Int:
    return value * 2
)
for x in xs:
    ...

let m = Map[String, Int]()
m.add(key: "a", value: 1)        # inserts or replaces, mutates
m.get("a")                       # Optional[Int]; m.get_or(key: "a", fallback: 0); m.contains("a"); m.length()
m.keys(); m.values()
let rows = m.entries().sorted(compare: fn(left: MapEntry[String, Int], right: MapEntry[String, Int]) -> Int:
    return left.key.compare(right.key)
)                                 # MapEntry has .key and .value; String.compare gives <0, 0, >0
```

- `List.concat(other)` returns a NEW list; to extend in place, `append` in a loop. `List` has no `clear()`; reassign `var xs = List[Int]()`.
- Do not rely on `Map.without(key)`: it can corrupt later lookups. Rebuild the map without that key instead.
- Map operations are slow compared with List; keep map operations per run to a few tens of thousands, or index with a `List[Int]`.
- Sorting needs an explicit comparator returning `Int`. `sorted` returns a new list.

## Strings (UTF-8; length counts Unicode scalars)

```manuscript
s.length(); s.is_empty(); s.upper(); s.lower(); s.trim()            # trim strips all Unicode whitespace
s.contains("x"); s.starts_with("x"); s.ends_with("x")
s.split(",")                      # List[String]; keeps empty fields: "a,,b" -> 3 parts
s.index_of("x")                   # Optional[Int]
s.slice(1, 4)                     # String, characters [1,4), out-of-range bounds are clamped
s.replace(old: "a", new: "b")     # first occurrence only
s.repeat(3) / s.pad_start(...) / s.replace_all(...) return Result: add .unwrap()
s.parse_int()                     # Optional[Int]; accepts signs, so validate digits first when the spec is strict
s.scalar_values()                 # List[Int] of code points: s.scalar_values() for loops over characters
s.to_bytes()                      # Bytes, what stdout().write wants
"{a}{b}"                          # interpolation; Int values interpolate directly
```

For many appends use `StringBuilder` (`import {StringBuilder} from "@std/string.ms"`): `let sb = StringBuilder()`, `sb.append(text)`, `sb.freeze()`.
`import {BytesBuilder} from "@std/bytes.ms"`: `append(byte)`, `freeze()` then `.to_text()` (Optional[String]).
Compare characters through `scalar_values()` codes: `0` is 48, `A` is 65, `a` is 97, space 32, tab 9, newline 10, `(` 40, `)` 41.

## Loops

```manuscript
var i = 0
while i < 10:
    i = i + 1
    if i == 3:
        continue
    if i == 8:
        break
for x in xs:
    ...
```

## Typical mistakes

- Forgetting `try`/`.unwrap()` on `Optional` and `Result` values.
- Using a reserved word (`from`, `unit`) as a variable name.
- A bare `{` in a string literal.
- Expecting `String.split` with a limit to keep the remainder in the last part (it drops it): split with `index_of` by hand.
- Integer math: `/` truncates; `%` of negatives follows the sign of the dividend.
