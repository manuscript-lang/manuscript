+++
title = "Optional values"
weight = 4
+++

# Optional values

Use `T?` when a value may be absent: an optional name, a failed lookup, or text that might not contain a number. It holds a `T` or `none`; a plain `T` becomes present wherever a `T?` is expected. `none` needs no import.

Save as `greeting.ms` and run `ms run greeting.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"Hello, Ada!\nHello, guest!\n"} -->
```manuscript
fn greeting(name: String?) String:
    return "Hello, {name.get("guest")}!"

export fn main() Int:
    print(greeting("Ada"))
    print(greeting())
    return 0
```

```text
Hello, Ada!
Hello, guest!
```

`get("guest")` supplies a fallback only when the value is absent. An empty string is still present. There is no `some(...)` constructor.

`T?` is the only spelling; `Optional[T]` is rejected. It applies to the type before it, so a function type needs parentheses: `fn(Int) Int?` returns an optional, `(fn(Int) Int)?` is an optional function.

A parameter or record field of type `T?` with no default is `none` when omitted, so `= none` is never written; a plain `T` passed for it wraps without `some`.

`T?` is an invariant enum. `none` takes its type from the expected type, so the type is written on the binding; a bare `let x = 1` is an `Int`, not an `Int?`.

This complete negative example is intentionally rejected. Save it as `example.ms` and run `ms check example.ms`:

<!-- manuscript-example: {"mode":"reject","stderr_contains":["cannot infer constructor type argument T"]} -->
```manuscript
export fn main() Int:
    let explicit: String? = none
    // Rejected: no type determines the absent payload.
    let unknown = none
    // Wrapped: an annotated binding expects an Optional.
    let wrapped: String? = "Ada"
    return 0
```

The diagnostic includes `cannot infer constructor type argument T`.

There is no implicit unwrapping or flattening: `Int??` differs from `Int?`. `Result[T, E]` likewise needs both arguments determined, possibly from the expected type. See [compatibility and expected types](compatibility.md).

## Passing optional arguments

An argument for a standard `T?` parameter may be a plain `T`; it is wrapped as the present case. An argument already `T?` passes unchanged, including `none`.

Save this complete example as `example.ms` and run `ms run example.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"true\nfalse\ntrue\ntrue\n"} -->
```manuscript
import Queue from "@std/collections/queue.ms"

export fn main() Int:
    var bounded = Queue[Int](capacity: 1)
    var unbounded = Queue[Int]()
    print(bounded.enqueue(3))
    print(bounded.enqueue(4))
    print(unbounded.enqueue(3))
    print(unbounded.enqueue(4))
    return 0
```

```text
true
false
true
true
```

- Applies to functions, methods, function values, constructor fields, and enum payloads.
- Wraps exactly one layer: an `Int?` fits `Int??`, a bare `Int` does not.
- The expression evaluates once, in argument order. Zero, `false`, and empty values stay present.
- Generic inference matches either the whole optional or its payload: `fn present[T](value: T?) T?` infers `T = Int` from `present(4)`. The payload type also gives context to an empty list or incomplete constructor.
- A `T?` parameter or field with no default is `none` when omitted.
- The same wrapping applies wherever a `T?` is expected: an annotated binding, an assignment, a return, a field or payload, a default, or a collection element (`let id: Int? = 3`). A user-defined `Optional` gets no wrapping.

See [declarations and calls](../functions/declarations-and-calls.md#argument-names).

## Checking and extracting values

Receiver methods:

| Method | Behavior |
| --- | --- |
| `is_some() Bool` | Whether the optional contains a value, including `false`, zero, or an empty string |
| `is_none() Bool` | Whether the optional is absent |
| `get(default: T?) T` | Return the contained value, or `default` when absent; without a default, [fault](../errors/faults.md) with `called Optional.get() on none` |
| `map[U](transform: fn(T) U) U?` | Transform a present payload once; preserve absence |
| `and_then[U](transform: fn(T) U?) U?` | Return the callback's Optional when present; preserve absence |
| `get_or_else(create: fn() T) T` | Return the contained value, or call `create` once when absent |
| `or_else(create: fn() T?) T?` | Keep a present Optional or call `create` once when absent |

Fallback for routine absence:

Save this complete example as `example.ms` and run `ms run example.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"Ada\nAnonymous\n"} -->
```manuscript
fn display_name(name: String?) String:
    return name.get("Anonymous")

export fn main() Int:
    print(display_name("Ada"))
    print(display_name())
    return 0
```

```text
Ada
Anonymous
```

`get(default)` always evaluates its argument. Use `get_or_else` when the fallback costs work:

Save this complete example as `example.ms` and run `ms run example.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"Anonymous\n"} -->
```manuscript
fn display_name(name: String?, create: fn() String) String:
    return name.get_or_else(create)

export fn main() Int:
    print(display_name(none, fn: "Anonymous"))
    return 0
```

```text
Anonymous
```

Prefer `if let` to test and unwrap in one step over `is_some()` then `get()`; `ms lint` reports a `get()` with no default as advisory **MSL110**, because it faults on `none`; pass a default or unwrap with `if let`. For a map lookup, write `m.get_or(key, fallback)` or `m[key]` (which faults when absent) instead of `m.get(key).get(fallback)` or `m.get(key).get()`:

Save this complete example as `example.ms` and run `ms run example.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"Hello, Ada\nHello!\n"} -->
```manuscript
fn greet(name: String?) String:
    if let value = name:
        return "Hello, " + value
    return "Hello!"

export fn main() Int:
    print(greet("Ada"))
    print(greet())
    return 0
```

```text
Hello, Ada
Hello!
```

Extraction returns the payload itself: no clone, no flattening. `map` transforms a payload; `and_then` chains an operation that returns an Optional:

Save this complete example as `example.ms` and run `ms run example.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"42\ntrue\n"} -->
```manuscript
fn first_number(text: String?) Int?:
    return text.map(fn value: value.trim().clone()).and_then(fn value: value.parse_int())

export fn main() Int:
    print(first_number(" 42 ").get(0))
    print(first_number("no number").is_none())
    return 0
```

```text
42
true
```

`map` keeps nesting if its callback returns an Optional; `and_then` does not. Callbacks run in the caller's context; faults and cancellation propagate.

[`if let`](../control-flow/conditionals.md#unwrapping-an-optional-or-result) binds the payload for a block, with optional `else`:

Save this complete example as `example.ms` and run `ms run example.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"Ada\nAnonymous\n"} -->
```manuscript
fn display_name(name: String?) String:
    if let value = name:
        return value.clone()
    return "Anonymous"

export fn main() Int:
    print(display_name("Ada"))
    print(display_name())
    return 0
```

```text
Ada
Anonymous
```

A [match](../control-flow/pattern-matching.md) on an Optional writes the present arm as a bare lowercase name beside `none:`; `v:` binds the payload. A two-arm match is reported by `ms lint` as MSL108. Use [Result](../errors/results.md) when failure needs an explanation; `try` propagates only `Result` errors.

## Keep two kinds of absence distinct

Nested optionals are useful when absence has two meanings. A lookup can fail to find a setting, while a setting that exists can deliberately have no value. `String??` keeps those states separate: the outer layer describes whether the setting was found, and the inner layer describes its value.

Save as `setting.ms` and run `ms run setting.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"missing\ncleared\nAda\n"} -->
```manuscript
fn describe(setting: String??) String:
    if let value = setting:
        return value.get("cleared")
    return "missing"

export fn main() Int:
    let missing: String?? = none
    let cleared: String? = none
    let named: String? = "Ada"
    print(describe(missing))
    print(describe(cleared))
    print(describe(named))
    return 0
```

```text
missing
cleared
Ada
```

Passing `cleared` wraps its `String?` in one present outer layer; it does not discard the inner `none`. Passing `missing` already has the required type, so it is unchanged. Use an explicit annotation for such values so the intended layer is clear. For a simple optional name, a single `String?` remains the better model.

## Optional chaining

`a?.b` reads `b` when `a` is present and is `none` otherwise. The result is optional (`B?`), and stays `B?` rather than `B??` when `b` is already optional. The rest of the chain runs only when `a` is present, so `a?.f(args)` evaluates `args` only then, and `a?.b?.c` stops at the first `none`. Write `?.` with no space on either side; the receiver must be optional, since `.` already reads a member of a value that is always present.

Save this complete example as `example.ms` and run `ms run example.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"5\ntrue\n"} -->
```manuscript
type Address:
    city: String?

type User:
    address: Address?

fn city_length(user: User?) Int?:
    return user?.address?.city?.length()

export fn main() Int:
    print(city_length(User(Address("Paris"))).get(0))
    print(city_length(User()).is_none())
    return 0
```

```text
5
true
```

A chain cannot move a field out of the optional it reads, so end an owned `String` or record field with `.clone()`.

A chain borrows the optional it starts from. When that place is a `var` (a `var` binding or parameter, or a field of one), the chain may call a `var fn` or change the payload, and the change lands in the optional itself, in place; on `none` nothing runs:

Save this complete example as `example.ms` and run `ms run example.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"1\ntrue\n"} -->
```manuscript
type Counter:
    n: Int

impl Counter:
    var fn bump() Int:
        self.n += 1
        return self.n

fn tick(var counter: Counter?) Int?:
    return counter?.bump()

export fn main() Int:
    var counter: Counter? = Counter(0)
    print(tick(var counter).get(0))
    var missing: Counter? = none
    print(tick(var missing).is_none())
    return 0
```

```text
1
true
```

Through a `let` or an undeclared-`var` parameter, `counter?.bump()` is rejected like any other change to that binding.

## Converting absence to a Result

- `ok_or[E = Error](cause: E?) Result[T, E]`: `ok` with the payload, or `error` with `cause` when absent. `cause` is evaluated eagerly; `E` may be any value type.
- `ok_or_else[E](create: fn() E) Result[T, E]`: calls `create` once, only on absence.

Omitting the cause yields an `Error` of kind `"ENOENT"` (the [default type argument](generics.md#default-type-arguments)). Its message records the source file and line of the `ok_or()` call, such as `missing value at src/main.ms:12`. Any function whose error type is `Error` can `try` it:

Save this complete example as `example.ms` and run `ms run example.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"8080\n"} -->
```manuscript
fn port_number(text: String) Int!:
    let port = try text.parse_int().ok_or()
    return ok(port)

export fn main() Int:
    let outcome = port_number("8080")
    if let port = outcome:
        print(port)
        return 0
    print(outcome.err().message)
    return 1

```

```text
8080
```

When fixing another error type, such as `Result[Int, ParseFailure]`, supply a cause explicitly.

[Result.to_optional](../errors/results.md#converting-success-to-an-optional) to keep success while discarding an error.

## Data modeling

A [record](records.md) can have optional fields such as `email: String?`. Manuscript has no nullable references; absence always lives in the declared type.
