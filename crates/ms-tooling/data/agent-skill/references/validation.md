# Validation and habits

After the last edit run `ms check <file>`, then run the program and read its output; `ms test`, then `ms verify --deny-warnings` (a single file: `ms verify main.ms`). `ms check --json` and `ms explain <code>` give detail; `--fix` applies mechanical repairs and rewrites the file, as does `ms fmt`, so re-read it. `ms lint` shows lint errors that `ms verify` can hide under warnings. Report compiled, executed and untested checks separately. Tests: [Testing](testing.md).

## Habits that fail, and the fix

| Not | Write |
| --- | --- |
| `!x`, `a ?? b`, `try f()`, `x or return y` | `not x`, `a.get_or(b)`, `f()?`, `if v := x:` |
| `x.len`, `x.length`, `x == none` | `x.length()`, `x.is_none()` |
| `(lo + hi) // 2` (`//` starts a comment) | `(lo + hi) / 2` (Int `/` truncates) |
| `ys := xs.sort()`, `print(xs.reverse())` (in place, return nothing) | `xs.sort()`; `xs.sorted()`, `xs.reversed()` |
| `bytes.to_string()` | `bytes.decode_utf8().ok_or(Error("not UTF-8"))?` |
| `const X = 1`, `# note`, `pass` | `X := 1`, `// note`, `void` |
| `a if c else b`, `-> T` | `if c: a else: b`, `fn f() T:` |
| `fn f(out: var T)`, `x: T = e` | `fn f(var out: T)`, `x: T := e` |
| `"total {n}"` | `f"total {n}"` |
| `"""text"""` on one line | `"""` ends its line; text next; closing `"""` alone |
| `for _ in xs`, `(String, Int)` | `for _i in xs`, a record |
| `f(x)?` statement on a non-Void result | `_done := f(x)?` |
| `s.parse_int()?` in an `Int!` function | `s.parse_int().ok_or(Error("bad number"))?` |
| `List<Int>`, `m.contains_key(k)`, `xs.remove_last()`, `set.insert(x)`, `r.is_err()`, `s.find(t)` | `List[Int]`, `m.contains(k)`, `xs.pop()`, `set.add(x)`, `r.is_error()`, `s.index_of(t)` |
| `xs.sort_by(f)`, `for b in s.as_bytes()` | `xs.sort(fn a, b: a.compare(b))`, `for b in values(s.as_bytes())` (`@std/bytes.ms`) |

The right-hand forms compile together:

<!-- complete: skill-habits.ms -->
```manuscript
import values from "@std/bytes.ms"

type Pair:
	name: String
	count: Int

fn parse_line(line: String) Pair?:
	parts := line.split(" ")
	if parts.length() != 2: return none
	n := parts.get_or(1, "").parse_int()
	if count := n:
		return Pair(name: parts.get_or(0, ""), count: count)
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

Also: `ms fmt` rewrites several imports into an `import (` block and collapses one-line `if` bodies. No date-only type: keep `"YYYY-MM-DD"` text and `parse_timestamp(f"{d}T00:00:00Z")`. `monotonic()` from `@std/time.ms` times code. Benchmarks are `bench "name":` blocks (`ms bench`, `keep` from `@std/test/bench.ms`). A `to_json` method with signature `fn T.to_json() JsonValue` is the JSON encoder.
