# Errors and optionals

`T?` is Optional[T]: values convert, `none` is absent. Extract with `if x := optional:` or `optional.get(default)`. `a?.field` chains absence. Postfix `?` propagates Result errors, not absence.

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

`ms run errors.ms` exits 0, without output.

`r?` extracts success or returns the error; the enclosing function must return a compatible Result. `if x := r:` handles success only. Add else for failure; there `.err()` yields the error directly, not Optional. Calling `.err()` on success faults.

Optional `.map(f)` preserves Result returns as `(T!)?`; handle both layers. Never accidentally drop a Result. Panic and failed no-default `.get()` fault; they are not catchable Results.
