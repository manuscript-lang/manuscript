# Errors and optionals

`T?` is Optional (`none` is absent; values convert, never write `some(x)`). `T!` is `Result[T, Error]`; `T!E` uses error type E. Return `ok(v)` or `error(Error("message", kind: "EINVAL"))`; `Error.kind` is `String?` (compare `e.kind.get_or("")`). A bare `return` in a `Void!` function means `ok`.

<!-- complete: errors.ms -->
```manuscript
fn parse(text: String) Int!:
	return text.parse_int().ok_or(Error("expected an integer"))

fn twice(text: String) Int!:
	value := parse(text)?
	return ok(value * 2)

fn main() Int:
	good := twice("21")
	if value := good:
		if value != 42: return 1
	else: return 2

	bad := parse("bad")
	if _value := bad: return 3
	else:
		if bad.err().message != "expected an integer": return 4
	return 0
```

- `r?` extracts success or returns the error; the function must return a compatible Result. `?` on an Optional returns `none` (or just returns in a `Void` function). `a?.field` is `(a?).field`.
- `if x := r:` handles success; its `else` sees `r.err()` (a fault on success). `.map` on an Optional keeps Result returns as `(T!)?`.
- Never drop a Result: `_done := f(x)?` or `void f(x)`. Panic and `get()` without a default fault; they are not catchable.
- A custom error is an enum: `Void!LibraryError`, `return error(LibraryError.NotFound(id))`. `?` needs the same error type in the caller. `opt.ok_or(MyErr.Bad)?` converts an Optional. `main` and tests use `Error`: translate with `r.map_error(fn e: Error(describe(e)))?`.
- In tests: `cause := expect_error(r)?`, `expect_true(r.is_ok())?` (`@std/test/test.ms`). A `List[String]` error cannot use `?` in a test: `.map_error(fn e: Error(e.join("; ")))`.
