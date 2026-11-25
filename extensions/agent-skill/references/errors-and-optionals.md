# Errors and optionals

`T?` is an Optional: a plain `T` converts, `null` is absent, there is no `some(...)`. An Optional has no methods; test it with `x == null` / `x != null` (afterwards an immutable `x` reads as its payload, and a `x == null` test that returns leaves it present for the rest of the block), give a fallback with `x or d`, and turn it into a Result with `ok_or(x, Error("what"))`. `if v := x { ... }` unwraps a Result, not an Optional. Postfix `?` unwraps a Result or an Optional and leaves the function on error or absence (`return null`, or just return in a `Void` function), so `a?.field` is `(a?).field` and needs an Optional, `Void`, or Result return that matches the operand. A `match` on an Optional writes `null =>` and a bare name for the payload. `m.get(k) or d` is `m.get_or(k, d)`.

`T!` is `Result[T, Error]` and `T!E` uses error type E (no space; `T!Error` is written `T!`). Return `ok(value)` or `error(reason)`; a `Void!` function may fall off the end. Error is a record: `Error("message", kind: "EINVAL")`; read `.message`.

<!-- complete: errors.ms -->
```manuscript
fn parse(text String) Int! {
    return ok_or(text.parse_int(), Error("expected an integer"))
}

fn twice(text String) Int! {
    value := parse(text)?
    return ok(value * 2)
}

fn main() Int {
    good := twice("21")

    if value := good {
        if value != 42 { return 1 }
    } else {
        return 2
    }

    bad := parse("bad")

    if _value := bad {
        return 3
    } else {
        if bad.err().message != "expected an integer" { return 4 }
    }

    return 0
}
```

`r?` extracts success or returns the error; the enclosing function must return a compatible Result. `if x := r { ... }` handles success only. Add else for failure; there `.err()` yields the error directly, not Optional. Calling `.err()` on success faults. `.err()` and `.get()` borrow the Result: use the error in place, or `.clone()` to keep it.

Optional `.map(f)` does not exist; a Result's `.map`, `.map_error`, `.and_then` and `.get_or` take the Result, so `.clone()` one you still need. Never accidentally drop a Result. Panic and `get()` on an error fault; they are not catchable Results.

A custom error type is any value, usually an enum with a payload per case. A function returns `String!LibraryError`, fails with `return error(LibraryError.NotFound(id))` and succeeds with `return ok(value)`. `?` needs the same error type in the enclosing function, so translate first with `map_error`; a `test` block's error type is `Error`. `Error.kind` is `String?` and any string works as a kind (`"EINVAL"`, `"ENOENT"`, `"ETIMEDOUT"`, `"ECANCELED"`): compare in place, `e.kind == "ENOENT"`.

<!-- complete: errors-custom.ms -->
```manuscript
enum LibraryError {
    NotFound(id Int)
    Closed
}

fn find(id Int) String!LibraryError {
    if id < 0 { return error(LibraryError.Closed) }
    if id > 9 { return error(LibraryError.NotFound(id)) }
    return ok(f"book {id}")
}

fn describe(e LibraryError) String {
    match e {
        NotFound(id) => return f"no book {id}"
        Closed => return "closed"
    }
}

fn title(id Int) String! {
    return find(id).map_error(e => Error(describe(e), kind: "ENOENT"))
}

fn first_even(xs List[Int]) Int? {
    for x in xs {
        if x % 2 == 0 { return x }
    }
    return null
}

fn doubled_first_even(xs List[Int]) Int? {
    n := first_even(xs)?
    return n * 2
}

fn is_missing(e Error) Bool => e.kind == "ENOENT"

fn main() Void! {
    print(title(3)?)
    r := title(42)
    if r.is_error() {
        print(r.err().message)
        print(is_missing(r.err()))
    }
    print(doubled_first_even([1, 4]) or -1)
    ok_value := ok_or(first_even([1]), Error("no even number"))
    if value := ok_value {
        print(value)
    } else {
        print(ok_value.err().message)
    }
    match first_even([2]) {
        null => print("none")
        n => print(n)
    }
}
```

In a test check outcomes with `expect_ok(r)?`, `expect_error(r)?` (returns the cause), `expect_some(x)?`, `expect_none(x)?`, `expect_true(r.is_error())?`, `expect_contains(text, part)?` from `@std/test/test.ms`. A `List[String]` error type cannot use `?` inside a test: convert with `.map_error(e => Error(e.join("; ")))` or check `.is_error()`. `r.err()` returns the enum case itself, handy for `expect_equal`. Add context with `wrap_error("read config", cause)` from `@std/core.ms`.
