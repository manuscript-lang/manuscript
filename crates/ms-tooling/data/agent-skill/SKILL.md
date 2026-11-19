---
name: manuscript
description: Design, write, check, test, ship and revise Manuscript programs and projects. Use for .ms source, ms.toml, Manuscript APIs, ownership, errors, concurrency, tests and compiler diagnostics.
---

# Write Manuscript

Written for Manuscript {{MS_VERSION}}. Compare with `ms --version`; when they differ, download the skill of your compiler's release. Manuscript is in beta: what the stability page lists is frozen; everything else may change. Never carry habits over from another language: when unsure of a name or a shape, ask the tools (`ms search_symbol`, `ms check`) instead of guessing.

## The model in six lines

Read [Mental model](references/mental-model.md) once; every rule below follows from it.

1. **Data is plain.** Records (`type`) and enums hold facts; functions and methods hold behavior. No classes, no inheritance, no null.
2. **One owner.** Every String, collection and record has exactly one owner. Reading and passing borrow; storing or a last use moves; `.clone()` is the only copy. No refcount, no GC: values are released at scope end.
3. **Failure is a value.** `T!` can fail, `T?` can be absent, and `?` hands either to your caller. Nothing is thrown. A fault (index out of range, `get()` on an error) ends the program or promise.
4. **Effects are visible.** A function is pure unless a `// ms: allow_effect` comment says what it reaches (console, files, network, clock). Pass capabilities in, not permissions up.
5. **Waiting is a value.** No `async`. A call that waits returns a running `Promise`; collect it with `.wait()`. State is never shared: one owner, everyone else sends messages over a `pipe`.
6. **The compiler is your reviewer.** Diagnostics read `<cause>; <fix>`. Add an enum case and let `ms check` list every `match` to update.

## Work in this loop

Details and project layout: [Workflow](references/workflow.md).

1. **Orient.** Existing code: read the file, its tests and `ms.toml`; match the style. New code: pick the smallest shape, one file for a script, `ms init <name>` for anything with tests or packages. Look names up with `ms search_symbol <words>`; never invent an API.
2. **Model the data first.** Types and enums, then the signatures that move them, then bodies. Decide ownership at the signature: borrow to read, `var` to change, `move` to take.
3. **Write the failure paths with the happy path**, not after: every parse, lookup and I/O call returns a Result or Optional.
4. **Check early and often.** `ms check --fix <file>`, fix what remains by the message, `ms fmt`.
5. **Test the rules** that cost something when wrong: a `test "name":` beside the code, then `ms test`. Run the program and look at its output ([Testing](references/testing.md)).
6. **Verify.** `ms verify --deny-warnings` (a single file: `ms verify main.ms`), then `ms build` to ship. Report what you ran and what you did not.

## Reach for this

| Need | Use |
| --- | --- |
| A fact with fields / one of several states | `type` / `enum` + flat `match` |
| Derive a list from a list | pipeline `xs \| .filter(f) \| .map(g) \| .sum()` |
| Build a Map, change a `var` | `for` loop |
| Can fail / may be absent | `T!` + `?` / `T?` + `if v := o:` or `get_or` |
| Read, write, or take a value | plain parameter / `var` parameter / `move` parameter |
| A resource (file, socket, stream) | bind it; it closes at scope end; `close()` moves it |
| Several waits at once | start promises, `wait_all` ([Effects and concurrency](references/effects-and-concurrency.md)) |
| State shared by handlers or tasks | one owner promise + a `pipe` ([Servers and state](references/servers-and-state.md)) |
| Text, bytes, offsets | [Text and bytes](references/text-and-bytes.md) |
| Several files, packages, workspaces | [Projects and packages](references/projects-and-packages.md) |
| Behavior of an interface | `interface` + methods beside the type; generics with bounds |

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

- Bindings: `x := e` (immutable), `var x = e`. Types: Int, Float, Bool, String, Void; `true`, `false`, `void`.
- Functions: `fn f(x: Int, n: Int = 1) Int:`, called `f(2, n: 3)`. Inline body is an expression; a block uses `return`. Closure: `fn x: x + 1`. Generics: `fn id[T](x: T) T: x`.
- Control: `if`/`else`, `while`, `for x in xs:`, `for i in 0..n:` (excludes n), `and or not`. Expression form: `if c: a else: b`.
- Collections need no import: `[1, 2]`, `Map[String, Int]()`, `Set[Int]()`. `m.get(k)` is Optional, `m.get_or(k, d)` has a fallback; `xs.slice(a, b)` is a Result.
- Imports: `import a, b from "./other.ms"`, `import sqrt from "@std/math/math.ms"`; `export` shares a declaration. `ms search_symbol <name>` prints the import line.
- Text: `"plain"` never interpolates, `f"total {n}"` does, `r"\d+"` is raw, `"""` opens multi-line text. `s.length()` counts **bytes**.
- `?` unwraps a Result or an Optional and returns early on error or absence.
- Not in the language: `~ & | ^ << >>` (use `bit_and`, `shift_left` ... from `@std/math/math.ms`), `assert` (use `expect_equal(...)?`), tuples, `try`, `async`, static methods (write `new_store()`), `some(x)` (an Optional takes the value itself), `x == none` (use `is_none()`).

## Compiler rules

1. **One owner.** "Moved here but used again": clone at the store, or borrow instead. While a binding borrows from `xs`, do not change `xs`.
2. **`?` needs a matching return type.** A `Result` needs a `Result` function; an Optional needs an Optional or `Void` function. A Result is never dropped: `_done := f(x)?` or `void f(x)`.
3. **Names are exact.** `append` not `push`, `contains` not `contains_key`, `pop`, `is_error`, `length()` with parentheses. Check [Standard calls](references/standard-calls.md).
4. **Shapes are fixed.** Records not tuples, `List[Int]` not `List<Int>`, `not x` not `!x`, a bare `_` is no name (`_i`), reserved words are no names.
5. **Close consumes.** `file.close()` moves `file`; use it once, then never again. Usually you close nothing: scope end does it.

## References

- Why and how: [Teaching Manuscript](references/teaching.md) (explaining the language to a programmer), [Mental model](references/mental-model.md), [Workflow](references/workflow.md), [Testing](references/testing.md), [Validation and habits](references/validation.md).
- Copy from: [Idioms](references/idioms.md) (thirteen complete programs).
- Names: [Standard calls](references/standard-calls.md), [Standard modules](references/standard-modules.md).
- Language: [Program structure](references/program-structure.md), [Values and control](references/values-and-control.md), [Types and functions](references/types-and-functions.md), [Collections and pipelines](references/collections-and-pipelines.md), [Text and bytes](references/text-and-bytes.md).
- Failure and ownership: [Errors and optionals](references/errors-and-optionals.md), [Ownership and cleanup](references/ownership-and-cleanup.md).
- Systems: [Projects, ms.toml and packages](references/projects-and-packages.md), [Effects and concurrency](references/effects-and-concurrency.md), [Servers and state](references/servers-and-state.md).
