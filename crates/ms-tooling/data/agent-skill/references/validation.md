# Validation

After the final edit, run `ms check app.ms`, then `ms run app.ms` and verify behavior. `ms test` runs tests; `ms verify` checks projects. `--deny-warnings` rejects warnings.

`ms check app.ms --json` gives structured diagnostics. Apply indicated repairs; `--fix` applies machine fixes, then recheck. `ms explain <code>` explains diagnostics. Acceptance does not prove runtime behavior or speed.

<!-- complete-test: arithmetic.ms -->
```manuscript
import expect_equal from "@std/test/test.ms"

fn twice(value: Int) Int: value * 2

test "twice":
	expect_equal(twice(21), 42)?
```

Assertions return Results; `?` fails the test on error. Tests need no main. `bench "name":` introduces benchmark bodies.

Test success, failure and boundary inputs. Never expect exceptions. Avoid undeclared assignment, `try`/`await`, unwrap-style calls, `def`, enum `case`, or methods inside type bodies. Use `:=`, postfix `?`, `fn Type.method` and explicit returns instead.

For additional APIs, inspect `ms search_symbol` signatures/imports. Report compiled, executed and untested checks separately.

## Habits from other languages

- Methods always take parentheses, even with no arguments: `xs.length()`, `name.length()`, `opt.is_none()`; `xs.length` is a method value, not an Int. Test absence with `x.is_none()` or `x.is_some()`, never `x == none`. Write `not x` (no `!x`), `f(x)?` (no `try`), `fn f() Result[Int, Error]:` (no `->`), `"\{ \}"` for literal braces in text, and `else:` only after an indented `if` block.
- Inside `{}` of an `f` string, write quotes plainly: `f"{xs.join(", ")}"`, never `\"`. `?.` chains an Optional only; to use a Result's value write `(r?).abs()`. In a `Void!` function a bare `return` means `return ok()`; other Result functions need `ok(value)` or `error(e)`.

Each row is a shape agents wrote that fails; the right column compiles.

| Not | Write |
| --- | --- |
| `!x`, `a ?? b`, `try f()`, `x or return y` | `not x`, `a.get(b)`, `f()?`, `if v := x:` then use `v` |
| `x.len`, `x.length`, `x == none` | `x.length()`, `x.is_none()` |
| `const X = 1`, `# note`, `pass` | `X := 1`, `// note`, `void` |
| `a if c else b`, `-> T` | `if c: a else: b`, `fn f() T:` |
| `if c: f() else: g()` as a statement | `if c:` and `else:` on their own lines, bodies indented |
| `fn f(out: var T)`, `x: T = e` | `fn f(var out: T)`, `x: T := e` |
| `"total {n}"` (plain text never interpolates) | `f"total {n}"` |
| `"""text"""` on one line | `"""` ends its line; the text starts on the next line and the closing `"""` stands alone (`r"""` the same, braces literal) |
| `for _ in xs` | `for _i in xs`; a bare `_` is not a name |
| `(String, Int)`, `[A, B]` tuples | a record: `type Pair:` with fields |
| `f(x)?` as a statement on a non-Void result | `_done := f(x)?` (a leading `_` marks it unused) |
| `s.parse_int()?` (it returns `Int?`, not a Result) | `s.parse_int().ok_or(Error("bad number"))?` or `s.parse_int().get(0)` |
| `List<Int>`, `Map<K, V>` | `List[Int]`, `Map[K, V]` |
| `r?.abs()` on a Result | `(r?).abs()`; `?.` is for Optionals only |
| `m.contains_key(k)`, `xs.remove_last()` | `m.contains(k)`, `xs.pop()` |
| `xs.sort_by(f)`, `for b in s.as_bytes()` | `xs.sort(fn a, b: a.compare(b))`, `for b in values(s.as_bytes())` with `import values from "@std/bytes.ms"` |
| `set.insert(x)`, `r.is_err()`, `s.find(t)` | `set.add(x)`, `r.is_error()`, `s.index_of(t)` |

The right-hand forms of this table, in one compiling program:

<!-- complete: skill-habits.ms -->
```manuscript
import values from "@std/bytes.ms"

type Pair:
	name: String
	count: Int

fn parse_line(line: String) Pair?:
	parts := line.split(" ", none)
	if parts.length() != 2: return none
	n := parts.get(1, "").parse_int()
	if count := n:
		return Pair(name: parts.get(0, ""), count: count)
	return none

fn bump(var seen: Set[String], word: String) Int:
	seen.add(word)
	return seen.length()

fn total(var counts: Map[String, Int], items: List[Pair]) Int:
	var sum = 0
	for pair in items:
		if counts.contains(pair.name.clone()): sum += 1
		counts[pair.name.clone()] = counts.get_or(pair.name, 0) + pair.count
	return sum

fn main() Void!:
	flag: List[Bool] := []
	brace := r"{}"
	esc := "\u{1}"
	var stack = [2, 1]
	stack.sort(fn a, b: a.compare(b))
	for b in values("ab".as_bytes()):
		void b
	void stack.pop()
	for _i in 0..2:
		var seen = Set[String]()
		void bump(var seen, "a")
	parsed := "7".parse_int().ok_or(Error("bad number"))?
	grid: List[List[Int]] := [[parsed]]
	r: Int! := ok(3)
	_checked := r?
	if r.is_error(): return error(Error("bad"))
	print(f"{brace}{esc}{flag.length()}{grid.length()}")
```
