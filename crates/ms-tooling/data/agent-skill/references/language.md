# Language

## Structure and control
- A file is a module: imports, then types, functions, methods. `main` takes no parameters and returns `Void`, `Int` (exit status) or `Void!` (an error prints and exits 1). Fields live in `type`; methods are `fn Type.name()` beside it with implicit `self`; `fn var` mutates the receiver. Build records `Counter(2)` or `Counter(n: 2)`; defaults allow omission; required fields come first. `export opaque` hides fields outside the file.
- `x := v` immutable (`x: T := v` typed), `var x = v` mutable; assignment needs `var`. An unused name starts with `_` (a bare `_` is no name). Int, Float, Bool, String, Void; numeric conversions are explicit.
- `if`/`else if`/`else` (else aligned with if), `while`, `for x in xs`, `for i in 0..n` (excludes n), `break`, `continue`, `and or not`; early exit `if c: return x`; expression `if c: a else: b`. Statement-form bodies go on their own indented lines.
- A function needs a result type (`Void` if none). Inline `fn f(x: Int) Int: x + 1` returns its expression; block bodies use `return`. Call `f(x)`, never `x.f()` unless declared with a receiver. Required parameters precede defaulted ones.

## Types and generics
Receiver methods satisfy an interface by shape (names, labels, types, `var`/`move` modes); a read-only method may satisfy a `var fn` operation. There are no `impl` blocks, static methods or constructors (write a free function `new_store()`). `fn var` is for methods only; a free function takes `var` on the parameter. Enum cases need no `case` keyword; build `Choice.Number(40)`; match exhaustively. Generics: `fn id[T](x: T) T`, `type Repository[T]:` with `fn var Repository[T: Searchable].add(item: T)`; combine bounds with `&`; lists are invariant (`fn report[T: Auditable](items: List[T])`). Bool and enums have no `compare`: rank them. Enums read and write JSON as the case name.

<!-- complete: types.ms -->
```manuscript
interface Apply:
	fn apply(value: Int) Int

type Offset:
	delta: Int

fn Offset.apply(value: Int) Int:
	return value + self.delta

fn use(value: Int, operation: Apply) Int:
	return operation.apply(value)

fn identity[T](value: T) T: value

enum Choice:
	Empty
	Number(value: Int)

fn number(choice: Choice) Int:
	match choice:
		Empty: return 0
		Number(value): return value

fn main() Int:
	chosen := Choice.Number(identity(40))
	if use(number(chosen), Offset(2)) == 42: return 0
	return 1
```

## Collections and pipelines
`[1, 2]`, `List[Int](reserve: 8)`, `Map[String, Int]()`, `Set[Int]()`; mutation needs `var`. `length()` counts a List, Map, Set or String (parentheses). `m.get(k)` is Optional, `m.get_or(k, d)` falls back; iterate `m.entries()` (`.key`, `.value`). `xs.get(i)` faults out of range: use `get_or(i, d)`. `xs.slice(a, b)` is a Result that errors when `b` is past the end, so skip a header with `xs.slice(1, xs.length()).get_or([])`; `String.slice` is a plain String. `Optional.get()` without a default is a lint error: unwrap with `if v := o:` or `get_or`. `m.filter/map/retain` take `fn k, v:`. `xs.sort()` and `reverse()` mutate and return nothing; `sorted()` and `reversed()` return copies.

`x | f(a: 1)` passes x first, `x | .m()` calls a method, `x | f?` propagates f's Result. List `.filter/.map/.sum` are methods; stream steps are imported functions.

<!-- complete: collections.ms -->
```manuscript
fn main() Int:
	values := [1, 2, 3, 4]
	total := values | .filter(fn x: x > 2) | .map(fn x: x * 2) | .sum()
	var counts = Map[String, Int]()
	counts["total"] = total
	if var n = counts["total"]?:
		n += 1
	if counts.get_or("total", 0) == 15 and values.length() == 4: return 0
	return 1
```
