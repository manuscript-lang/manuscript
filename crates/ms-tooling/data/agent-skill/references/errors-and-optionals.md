# Errors and optionals

`T?` means `Optional[T]`: T values convert to present optionals and `none` is absent. Bind a present value with `if value := optional:`; `optional.get(default)` supplies a fallback. `a?.field` chains absence. Postfix `?` propagates Result errors, not Optional absence.

`T!` means `Result[T, Error]`; `T!E` uses a specific error type. Return `ok(value)` or `error(reason)`. `Error("message", kind: "EINVAL")` is a concrete record; `.message` reads its text.

Save as `errors.ms`:

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

`ms run errors.ms` prints nothing and exits 0.

- `r?` extracts success or immediately returns the error. The enclosing function must return a compatible Result.
- In a Result's failure branch, `.err()` returns the error itself, not an Optional. Calling it on success faults. Never discard a Result accidentally.

`if value := result:` alone handles only success: add an else when failure needs handling. Optional `.map(f)` does not flatten Result returns: it produces `(T!)?`, so handle both layers. A panic or failed no-default `.get()` is a fault, not a catchable Result; use checked operations for expected failure.
