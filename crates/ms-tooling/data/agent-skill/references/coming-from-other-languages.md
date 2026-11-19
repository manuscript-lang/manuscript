# Coming from other languages

You already program in Go, Rust, TypeScript or Python, and your first drafts will carry their habits. Manuscript shares ideas with each, so map what you know onto it, then drop what does not apply. Read this once before writing; when a compiler error surprises you, find its row here.

## Map what you know

| You know | In Manuscript |
| --- | --- |
| Rust ownership | The same idea, simpler: one owner, borrow by default, `var` to change (written at the declaration and the call), `move` to take, `.clone()` to copy. There are no lifetime annotations; a function may return a borrow of its argument. |
| Go structs and interfaces | `type` plus methods beside it; interfaces are satisfied by matching method shapes, with no `implements`. Errors are values, but `T!` and `?` replace `if err != nil`. |
| TypeScript unions | `enum` with payload cases and an exhaustive `match`. No `null` or `undefined`: absence is `T?`. |
| Python scripts | Same brevity (`print`, f-strings, pipelines), but every type is checked and every failure is a returned value. |
| Exceptions | Do not reach for `try`/`throw`. A function returns `T!`, and the caller uses `?`. |
| `async`/`await`, goroutines, threads | A call that waits returns a running `Promise`; `.wait()` collects it. No shared mutable state: one owner and a `pipe`. |
| Classes and inheritance | A record, an enum, and an interface. Compose; do not extend. |
| Generics `List<T>` | `List[T]` with brackets; bounds as `T: Clonable & Comparable`. |

## Do this, not that

- **Ownership.** Passing and reading never copy. Before writing `.clone()`, ask whether borrowing, moving at the last use, or keeping an index works. When storing a borrowed value (a loop variable, a field, a parameter), `.clone()` at the store.
- **Failure.** Return `T!` from anything that can fail and write `?` at each call. Turn an Optional into an error with `.ok_or(Error("what and which input"))`. Do not look for `panic`, `unwrap` or `try`; a fault is a bug, not control flow.
- **Data.** Add a case to the `enum` instead of a flag field, then let `ms check` list every `match` to update. Use a record where you would use a tuple.
- **Effects.** Keep the core pure and give it capabilities (interface values) from `main`. Allow effects with the narrowest `// ms: allow_effect` line.
- **Waiting.** Start the promises, then `wait_all`. State that tasks share has one owner; tasks send it events through a `pipe`.
- **Names.** Do not translate: `append` not `push`, `contains` not `has`, `length()` with parentheses. Run `ms search_symbol <words>` before using any API you have not seen in this skill.
- **Text.** `length()` counts bytes and there is no `text[i]`. Decode Bytes before printing. Plain `"..."` never interpolates; use `f"..."`.
- **Cleanup.** Never write a `finally`, `defer` or `with`. A file, socket or stream closes at scope end. `close()` consumes the value, so call it only to handle a close error.

## Shape of a first program

Model the data, write the signatures with their ownership and failure types, then the bodies, then `main` as a thin edge. Check after each step.

```manuscript
type Task:
	title: String
	done: Bool = false

fn var Task.finish() Void:
	self.done = true

fn open_titles(tasks: List[Task]) List[String]:
	return tasks | .filter(fn t: not t.done) | .map(fn t: t.title.clone())
```

`tasks` is read, so it is borrowed; `finish` mutates its receiver, so it is `fn var`; the titles are cloned because the new list owns them.

## Explaining it to someone else

When the user asks you to teach or explain Manuscript, lead with the same order as above, keep sentences short, and show only code you have run: one owner per value, failure as a value, plain data, visible effects, waiting without a keyword, and a compiler whose messages say how to fix the error. Point to [Mental model](mental-model.md) for the reasons and [Workflow](workflow.md) for a first project.
