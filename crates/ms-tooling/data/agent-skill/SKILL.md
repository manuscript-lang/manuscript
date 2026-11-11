---
name: manuscript
description: Write, check, test, and revise idiomatic Manuscript programs. Use for .ms source, Manuscript APIs, ownership, errors, streams, and compiler diagnostics.
---

# Write Manuscript

Generated for Manuscript {{MS_VERSION}}. Compare with `ms --version`; regenerate this skill with the matching compiler when stale. Manuscript is in alpha: syntax and APIs may change.

## Core language

Use tabs for indentation. A trailing `:` opens a body; dedent ends it. A module contains imports and declarations; `main` is its entry point. Fields belong inside `type`; methods sit beside it with implicit `self`. `fn var` permits receiver mutation.

<!-- complete: skill-core.ms -->
```manuscript
type Counter:
	n: Int = 0

fn var Counter.add(value: Int) Unit:
	self.n += value

fn Counter.value() Int: self.n

// ms: allow_effect std.console.write
fn main() Unit!:
	value := "42".parse_int().ok_or(Error("expected an integer"))?
	var counter = Counter()
	counter.add(value)
	print(counter.value())
```

### Syntax and data

- Immutable: `x := e`, or `x: T := e`. Mutable: `var x = e`; assignment and content mutation require var. Basic types: Int, Float, Bool, String, Unit; literals: `true`, `false`, `unit`. Strings interpolate `"hello {name}"`.
- Functions declare parameter/return types: `fn f(x: Int, n: Int = 1) Int:`. Call `f(2, n: 3)`. Inline bodies return expressions; multiline bodies use `return`. Unit/Unit! may fall through. Main returns Unit, Int status, or Unit!.
- Generics: `fn identity[T](x: T) T: x`. Callback: `fn(Int) Int`; closure: `fn x: x + 1`.
- Control: `if`/`else if`/`else`, `while`, `for x in xs:`, `for i in 0..n:` (excludes n), `break`, `continue`; `and or not`. Prefer early exits: `if c: return x`. Expression: `if c: a else: b`.
- Import `name` with `import name from "./other.ms"`; `export` shares declarations. Standard paths start `@std/`. Construct records `Counter()` or `Counter(n: 2)`. Receiver methods satisfy matching interfaces; no impl blocks.
- `enum Choice:` declares cases `Empty` and `Value(n: Int)`. Construct `Choice.Value(2)`. `match choice:` uses arms `Empty:`, `Value(n):`, or `_:`; match exhaustively and keep it flat.
- Prelude collections: `[1, 2]`, `Map[String, Int]()`, `Set[Int]()`. List pipeline: `xs | .filter(fn x: x > 0) | .map(fn x: x * 2) | .sum()`. `x | f(a)` passes x first; `x | .m()` calls a method. Map `.get(k)` returns Optional; `.get_or(k, default)` supplies a fallback.

### Absence, errors and ownership

- `T?` is Optional: values convert, `none` is absent. Extract with `if x := optional:` or `.get(default)`. `a?.field` chains absence; postfix `?` is for Results only.
- `T!` is Result[T, Error]. Return `ok(value)`/`error(Error("message"))`; `r?` extracts success or returns the error from a compatible Result-returning function. Otherwise `if x := r:` handles success; in else, `r.err()` yields the error directly (`.message` reads its text). Never call it on success or accidentally drop a Result.
- Int/Float/Bool copy. Owned values can be borrowed by reads and moved into storage. Clone only for an independent owner, e.g. `names.append(user.name.clone())`. `fn add(var xs: List[Int]) Unit` is called `add(var xs)`; return parts of parameters by borrow without a marker. Closeable cleans up at scope end unless moved; no GC.
- `p.wait()` on Promise[T] returns T! once; no async/await keywords. Keep mutable state with one owner. Effects use narrow directives above functions, as shown; directives do not execute effects.

## Deep dives

- [Program structure](references/program-structure.md) covers modules, imports and main. Shows indentation, types and receiver methods. Use for file-layout details.
- [Values and control](references/values-and-control.md) covers bindings and literals. Shows branches, loops and range bounds. Use for control-flow details.
- [Types and functions](references/types-and-functions.md) covers signatures, generics and callbacks. Shows enums and interfaces. Use for reusable-operation details.
- [Errors and optionals](references/errors-and-optionals.md) separates absence from failure. Shows propagation and explicit handling. Use for nested-result details.
- [Ownership and cleanup](references/ownership-and-cleanup.md) explains borrows, moves and clones. Shows mutation and cleanup. Use for resource-lifetime details.
- [Collections and pipelines](references/collections-and-pipelines.md) covers construction, lookup and mutation. Distinguishes method and function pipelines. Use for collection-operation details.
- [Effects and concurrency](references/effects-and-concurrency.md) covers effects, promises and streams. Explains waiting and capture rules. Use for concurrent and streaming work.
- [Validation](references/validation.md) covers checks, tests and diagnostics. Includes a complete assertion. Use for testing and repair details.

## Verify

Run applicable `ms check`, `ms run` and `ms test` commands after editing. Check behavior, not just compilation; report unrun checks. Include imports. Prelude collections, Optional, Result, Error and print need none. For additional APIs, `ms search_symbol <words>` supplies signatures/imports; do not guess.
