---
name: manuscript
description: Guide for an agent that knows other languages: design, write, check, test, ship and revise Manuscript (.ms) programs and projects, including ms.toml, ownership, errors, concurrency, tests and compiler diagnostics.
---

# Write Manuscript

Written for Manuscript {{MS_VERSION}}. Compare with `ms --version`; when they differ, download the skill of your compiler's release. Manuscript is in beta: what the stability page lists is frozen; everything else may change.

You already know how to program; this teaches only the difference. Defaults from Go, Rust, TypeScript and Python are right about half the time. So: look up every name (`ms search_symbol <words>`), let `ms check --fix` correct shapes, and read each error (`<cause>; <fix>`). Carries over: records, enums with exhaustive `match`, generics, interfaces, closures, pipelines, tests beside code. Does not: exceptions, null, classes, inheritance, tuples, `async`, shared mutable state, GC, implicit copies, text indexing. [Coming from other languages](references/coming-from-other-languages.md) maps each habit; [Mental model](references/mental-model.md) gives the reasons.

## Six rules

1. **Plain data.** `type` and `enum` hold facts; functions and methods hold behavior.
2. **One owner.** Reading and passing borrow; `var` changes (declaration and call); storing or a last use moves; `.clone()` is the only copy.
3. **Failure is a value.** `T!` fails, `T?` may be absent, `?` hands either to the caller. A fault is a bug.
4. **Effects are visible.** `// ms: allow_effect` above a function that reaches console, files, network or clock. Pass capabilities in.
5. **Waiting is a value.** A waiting call returns a `Promise`; `.wait()`. Shared state: one owner and a `pipe`.
6. **The compiler reviews.** Add an enum case; `ms check` lists each `match` to update.

## Loop

Details: [Workflow](references/workflow.md).

1. Orient: read the code, tests, `ms.toml`; `ms search_symbol` before using any API.
2. Model types, then signatures (ownership, `T!`/`T?`), then bodies, then a thin `main`.
3. `ms check --fix`, `ms fmt`, fix by message.
4. Test the rules that cost something when wrong ([Testing](references/testing.md)); run the program on real input.
5. `ms verify --deny-warnings`; `ms build` to ship. Report what you ran and did not.

## Syntax card

Use tabs for indentation. A trailing `:` opens a body; dedent ends it. Methods sit beside their `type` with implicit `self`; `fn var` mutates the receiver, `fn move` consumes it.

<!-- complete: skill-core.ms -->
```manuscript
type Counter:
	n: Int = 0

fn var Counter.add(value: Int) Void:
	self.n += value

fn Counter.value() Int: self.n

// ms: allow_effect std.console.write
fn main() Void!:
	value := "42".parse_int().ok_or(Error("expected an integer"))?
	var counter = Counter()
	counter.add(value)
	print(counter.value())
```

- Bindings: `x := e` (immutable), `var x = e`. Functions: `fn f(x: Int, n: Int = 1) Int:` called `f(2, n: 3)`; inline body is an expression, a block uses `return`; closure `fn x: x + 1`; generics `fn id[T](x: T) T: x`.
- Control: `if`/`else`, `while`, `for x in xs:`, `for i in 0..n:` (excludes n), `and or not`, `if c: a else: b`.
- Collections need no import: `[1, 2]`, `Map[String, Int]()`, `Set[Int]()`; `m.get(k)` is Optional, `m.get_or(k, d)` falls back; `xs.slice(a, b)` is a Result.
- Imports: `import a, b from "./x.ms"`, `from "@std/math/math.ms"`; `export` shares. `ms search_symbol <name>` prints the import line.
- Text: `"plain"` never interpolates, `f"n {n}"` does; `length()` counts **bytes**.
- Absent from the language: `& | ^ << >>` (`bit_and`, `shift_left`... in `@std/math/math.ms`), `assert` (`expect_equal(...)?`), static methods (write `new_store()`), `some(x)`.

## First-build errors, most common first

Measured on failed first builds. Write the right column the first time.

| Error says | Cause | Write |
| --- | --- | --- |
| `moved here but used again` | a store or `move` parameter took it | `.clone()` at the store or call; or use it before the move |
| `cannot change X while Y borrows it` | `y := x.part`, `if v := m.get(k)`, a `for` or `match` binding still in use | end the binding with `.clone()` (`it := self.items[i].clone()`), or finish with `y` before changing `x` |
| `parameter X is not declared var` | mutated a plain parameter | `var x: T` in the signature **and** `f(var x)` at every call |
| `cannot assign immutable binding` | `x := 0` then `x = 1` | `var x = 0` |
| `standalone ? requires a Void success value` | `f(x)?` as a statement, f returns a value | `_done := f(x)?`, or `void f(x)` |
| `unknown binding unit` | invented a unit value | the Void value is `void`: `return ok(void)` or bare `return` |
| `?. needs an optional receiver` | `f()?.trim()` on a Result | `(f()?).trim()` or `v := f()?` |
| `? on an Optional ... must return` | `?` on `T?` in a `T!` function | `.ok_or(Error("..."))?` |
| `unknown member push / contains_key / keys on Set` | name from another language | `append`, `contains`, `values()`: `ms search_symbol` |
| `if binding requires an Optional or Result` | `if v := xs[i]:` | `xs[i]` is a value; use `xs.get_or(i, d)` or `m.get(k)` |
| `cannot move X out: it is borrowed` | stored a loop variable, parameter or field | `x.clone()` |
| `expected end of inline statement, found else` | `if c: a else: b` as a statement | `if c:` and `else:` on their own indented lines |
| `expected a name, found '_'`, `unexpected '#'` | habits | `_i`; `//` comments |
| `unknown type Bytes` | missing import | `import Bytes from "@std/bytes.ms"` |

A Result is never dropped; absent is `none`, never `some(x)`; `x.close()` consumes `x` and scope end already closes; names are exact ([Standard calls](references/standard-calls.md)).

## References

- Habits and method: [Coming from other languages](references/coming-from-other-languages.md), [Mental model](references/mental-model.md), [Workflow](references/workflow.md), [Testing](references/testing.md), [Validation and habits](references/validation.md).
- Copy from: [Idioms](references/idioms.md).
- Names: [Standard calls](references/standard-calls.md), [Standard modules](references/standard-modules.md).
- Language: [Language](references/language.md), [Text and bytes](references/text-and-bytes.md), [Errors and optionals](references/errors-and-optionals.md), [Ownership and cleanup](references/ownership-and-cleanup.md).
- Systems: [Projects and packages](references/projects-and-packages.md), [Effects and concurrency](references/effects-and-concurrency.md), [Servers and state](references/servers-and-state.md).
