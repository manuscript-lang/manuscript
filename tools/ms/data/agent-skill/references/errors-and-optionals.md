# Errors and optionals

`T?` is Optional[T]: values convert, `none` is absent. Extract with `if x := optional:` or `optional.get_or(default)`. Postfix `?` unwraps a Result or an Optional and leaves the function on error or absence (`return none`, or just return in a `Void` function), so `a?.field` is `(a?).field` and needs an Optional, `Void`, or Result return that matches the operand.

`T!` is Result[T, Error]; `T!E` uses error type E. Return `ok(value)` or `error(reason)`. Error is a record: `Error("message", kind: "EINVAL")`; read `.message`.

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

`r?` extracts success or returns the error; the enclosing function must return a compatible Result. `if x := r:` handles success only. Add else for failure; there `.err()` yields the error directly, not Optional. Calling `.err()` on success faults.

Optional `.map(f)` preserves Result returns as `(T!)?`; handle both layers. Never accidentally drop a Result. Panic and failed no-default `.get()` fault; they are not catchable Results.

A custom error type is any enum: `enum LibraryError:` with cases such as `NotFound(id: Int)`; a function returns `Void!LibraryError`, fails with `return error(LibraryError.NotFound(id))` and succeeds with `return ok(void)`. `?` needs the same error type in the enclosing function, and a `test` block's error type is `Error`, so in a test check the outcome with `expect_true(r.is_ok())?` or `expect_true(r.is_error())?` (also `expect_error`, `expect_none`, `expect_contains` from `@std/test/test.ms`). `Error.kind` is `String?` and any string works as a kind (`"EINVAL"`, `"ENOENT"`, `"ETIMEDOUT"`, `"ECANCELED"`): compare with `e.kind.get_or("")`.

`expect_error(r)` returns the cause, so write `cause := expect_error(r)?`. A `List[String]` error type cannot use `?` inside a test: convert with `.map_error(fn e: Error(e.join("; ")))` or check `.is_error()`.

With a custom error enum, an Optional converts with `opt.ok_or(VmError.BadJump)?`. In `main` or a test (error type `Error`), translate first: `r.map_error(fn e: Error(describe(e)))?`; `r.err()` returns the enum case itself, handy for `expect_equal`.
