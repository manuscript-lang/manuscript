# Coming from other languages

Your first drafts will carry habits from Go, Rust, TypeScript or Python. Find the habit; use the replacement.

| Habit | Manuscript |
| --- | --- |
| Rust lifetimes, `&`, `&mut` | None to write: borrow by default, `var` to change (declaration and call), `move` to take, `.clone()` to copy. |
| Go `if err != nil` | Return `T!`; call with `?`. |
| Exceptions, `try`, `panic`, `unwrap` | `T!` and `?`. A fault is a bug, not control flow. |
| `null`, `undefined`, `Option<T>` | `T?`; unwrap with `if v := o:`, `get_or(d)` or `?`. Never `some(x)`. |
| Classes, inheritance | Record + enum + interface (met by method shape, no `implements`). |
| Tuples | A small record. |
| `async`/`await`, goroutines | A waiting call returns a `Promise`; `.wait()`. Shared state: one owner + `pipe`. |
| `finally`, `defer`, `with` | None; resources close at scope end. |
| `List<T>`, `!x`, `x == none` | `List[T]`, `not x`, `x.is_none()`. |
| `xs.push`, `m.has`, `xs.len` | `xs.append`, `m.contains`, `xs.length()`. Look up: `ms search_symbol`. |
| `text[i]`, char counts | None: `length()` counts bytes; use `chars()` or `slice` with byte offsets. Decode Bytes before printing. |
| `"hello {name}"` | `f"hello {name}"`; plain `"..."` never interpolates. |

Before `.clone()`, try borrowing, moving at the last use, or keeping an index. Add an enum case rather than a flag field. Keep logic pure; wire effects in `main`.

To explain Manuscript to a person: one owner per value, failure as a value, plain data, visible effects, waiting without a keyword, a compiler that says how to fix errors. Short sentences; show only code you ran. Reasons: [Mental model](mental-model.md).

```manuscript
fn first_even(xs: List[Int]) Int?:
	return xs.find(fn x: x % 2 == 0)

fn doubled(xs: List[Int]) Int!:
	n := first_even(xs).ok_or(Error("no even number"))?
	return ok(n * 2)
```
