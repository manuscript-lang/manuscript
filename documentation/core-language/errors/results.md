+++
title = "Expected failures with Result"
weight = 1
+++

# Expected failures with Result

Use `Result[T, E]` when an operation succeeds with `T` or fails with an expected error `E`. `E` may be any value type. Most failures use the prelude record [`Error`](#the-error-record). `Result`, `ok`, `error`, and `Error` are in the prelude.

Return `ok(value: ...)` for success and `error(cause: ...)` for failure. Both are ordinary values. A caller can test it with `is_error()`, read the success path with `if let`, or pass the error back with `try`. Validate runtime input with ordinary conditions before doing the work.

## Validate a value and show the outcome

Save this as `quantity.ms` and run `ms run quantity.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"Quantity: 3\nQuantity must be positive\n"} -->
```manuscript
fn quantity(value: Int) Int!:
    if value <= 0:
        return error(Error("Quantity must be positive", kind: "EINVAL"))
    return ok(value)

fn show(value: Int) Unit:
    let outcome = quantity(value)
    if let quantity = outcome:
        print("Quantity: {quantity}")
        return
    print(outcome.err().message)

export fn main() Int:
    show(3)
    show(0)
    return 0
```

```text
Quantity: 3
Quantity must be positive
```

Both calls return normally. The second returns an error value, and `show` chooses how to present it. A quantity of zero is ordinary input the application can reject; it does not mean the program has broken an invariant. The return type makes that possibility visible before the caller runs the function.

The success branch binds the quantity and returns after printing it. Only the error path reaches `err()`, so the cause remains available for presentation. `err()` faults on a success; keep it on a path where failure is established. Use [`try`](propagation.md) when the caller should pass the cause on instead of presenting it here.

## Shorthand: `T!` and `T!E`

`T!` is `Result[T, Error]` and `T!E` (with no space before `E`) is `Result[T, E]`, mirroring `T?` for optionals. Use `T!E` for a failure that is not an `Error`. `Result[T, E]` stays valid. Save this program as `port.ms` and run `ms run port.ms`; it prints `8080`:

<!-- manuscript-example: {"mode":"run","stdout":"8080\n"} -->
```manuscript
fn parse_port(text: String) Int!:
    let port = try text.parse_int().ok_or()
    return ok(port)

export fn main() Int:
    let outcome = parse_port("8080")
    if let value = outcome:
        print(value)
        return 0
    print(outcome.err())
    return 1
```

Suffixes apply left to right: `Int?!` is `Result[Int?, Error]` and `Int!?` is `Optional[Result[Int, Error]]`. A function type needs parentheses first, as with `?`: `(fn() Int)!`.

## The Error record

`Error` is a plain record with the following declaration shape. This is API reference, not a type to redeclare in your program:

```manuscript
export type Error:
    message: String
    kind: String? = none
    details: Map[String, String] = Map[String, String]()
```

- `message` is the text to show a person.
- `kind` is an optional short code a caller can branch on; it is `none` when no code fits (the default). The standard library uses POSIX errno names such as `"ENOENT"` (not found), `"EEXIST"`, `"EACCES"`, `"EINVAL"` (invalid input), `"EBADMSG"` (malformed data), `"EOVERFLOW"` (limit exceeded), `"ERANGE"`, `"ENOTSUP"`, `"EBADF"` (closed), `"EIO"`, `"EAGAIN"`, `"EBUSY"`, `"ETIMEDOUT"`, and `"ECANCELED"`; the full list is in the `Error` declaration. Your own code uses any string, preferably with its own prefix such as `"EQUOTA"`. A literal, or any string of at most 15 bytes, never allocates.
- `details` holds extra named context as text, such as a path or a line number.

Build one with the record call. There is no separate constructor and no namespace. Save the following as `users.ms` and run `ms run users.ms`; it prints `negative id`, then `missing 7: no such user`:

<!-- manuscript-example: {"mode":"run","stdout":"negative id\nmissing 7: no such user\n"} -->
```manuscript
fn find_user(id: Int) String!:
    if id < 0:
        return error(Error("negative id", kind: "EINVAL"))
    return error(Error("no such user", kind: "ENOENT", details: {"id": id.to_string()}))

fn describe(id: Int) String:
    let outcome = find_user(id)
    if let name = outcome:
        return name.clone()
    let cause = outcome.err()
    if cause.kind == "ENOENT":
        return "missing {cause.details["id"]}: {cause.message}"
    return cause.message.clone()

export fn main() Int:
    print(describe(-1))
    print(describe(7))
    return 0
```

Standard-library failures are `Error` values too: branch on `kind`, read `details`, and do not import a per-module error type. Two errors are equal when their three fields are equal.

## Returning a domain error

An `Error` fits most code. Use your own type as `E` when callers need typed payloads or exhaustive cases. Save this module as `discount.ms`; the complete programs below import it from the same directory. `ms check discount.ms` prints `Checked discount.ms`.

<!-- manuscript-example: {"mode":"check"} -->
```manuscript
import Decimal from "@std/math/decimal.ms"

export enum DiscountError:
    InvalidPrice
    InvalidPercent

export fn discount(price: Decimal, percent: Decimal) Decimal!DiscountError:
    if price < 0d:
        return error(InvalidPrice)
    if percent < 0d or percent > 100d:
        return error(InvalidPercent)

    return ok(price * (1d - percent / 100d))
```

The function validates inputs, returns an explicit error for each failure, and wraps the result in `ok`. The enum distinguishes two decisions a caller can make: correct the price or correct the percentage. Its cases are values, not exceptions. Adding a case changes the set of outcomes callers need to consider.

Zero and a 100 percent discount are accepted here. Validation rules belong to the application; choose them deliberately rather than using a fault to reject an expected input.

## Handling the result

Save as `discount-message.ms` beside `discount.ms` and run `ms run discount-message.ms`. It prints a price, then the two validation messages:

<!-- manuscript-example: {"mode":"run","stdout":"Discounted price: 18\nPrice must not be negative.\nPercent must be between 0 and 100.\n","build_files":{"discount.ms":"import Decimal from \"@std/math/decimal.ms\"\n\nexport enum DiscountError:\n    InvalidPrice\n    InvalidPercent\n\nexport fn discount(price: Decimal, percent: Decimal) Decimal!DiscountError:\n    if price < 0d:\n        return error(InvalidPrice)\n    if percent < 0d or percent > 100d:\n        return error(InvalidPercent)\n\n    return ok(price * (1d - percent / 100d))"}} -->
```manuscript
import Decimal from "@std/math/decimal.ms"
import DiscountError, discount from "./discount.ms"

fn discount_message(price: Decimal, percent: Decimal) String:
    let outcome = discount(price, percent)
    if let value = outcome:
        return "Discounted price: {value}"
    match outcome.err():
        InvalidPrice:
            return "Price must not be negative."
        InvalidPercent:
            return "Percent must be between 0 and 100."

export fn main() Int:
    print(discount_message(20d, 10d))
    print(discount_message(-1d, 10d))
    print(discount_message(20d, 110d))
    return 0
```

The success branch binds the price. The remaining path handles each domain error explicitly, so a caller can tell which input needs correcting. If this layer cannot recover or present the error, [propagate it with try](propagation.md).

## Checking, extracting, and composing

| Method | Behavior |
| --- | --- |
| `is_ok()`, `is_error()` | Test the case, including successful zero, false, or Unit values |
| `get(default: T?) T` | Return the successful payload, or `default` on an error; without a default, [fault](faults.md) on an error |
| `err() E` | Return the error payload; fault on success |
| `get_or_else(create: fn(E) T) T` | Return the successful payload, or call `create` once with the original error on failure |
| `or_else(create: fn(E) Result[T, E]) Result[T, E]` | Keep a success, or call `create` once with the original error and return its Result |
| `map_error[F](transform: fn(E) F) Result[T, F]` | Transform an error once; preserve a success unchanged |
| `map[U](transform: fn(T) U) Result[U, E]` | Transform success once; preserve an error unchanged |
| `and_then[U](transform: fn(T) Result[U, E]) Result[U, E]` | On success, return the callback's Result; preserve an existing error |

`map` wraps the callback's value in `ok`, even if it is a Result or Optional. `and_then` requires the same `E`; translate unrelated errors with ordinary functions.

Save as `discount-text.ms` beside `discount.ms` and run `ms run discount-text.ms`; it prints `18`. The mapping changes the successful value to text while retaining the error type and cause:

<!-- manuscript-example: {"mode":"run","stdout":"18\n","build_files":{"discount.ms":"import Decimal from \"@std/math/decimal.ms\"\n\nexport enum DiscountError:\n    InvalidPrice\n    InvalidPercent\n\nexport fn discount(price: Decimal, percent: Decimal) Decimal!DiscountError:\n    if price < 0d:\n        return error(InvalidPrice)\n    if percent < 0d or percent > 100d:\n        return error(InvalidPercent)\n\n    return ok(price * (1d - percent / 100d))"}} -->
```manuscript
import Decimal from "@std/math/decimal.ms"
import DiscountError, discount from "./discount.ms"

fn discounted_text() String!DiscountError:
    return discount(price: 20d, percent: 10d).map(fn value: value.to_string())

export fn main() Int:
    let outcome = discounted_text()
    if let value = outcome:
        print(value)
        return 0
    print(outcome.err())
    return 1
```

Callbacks run sequentially in the caller's context; faults and cancellation propagate normally. `get` reports `called Result.get() on error`; use it only when success is established. Routine failures use a fallback, `if let`, or `try`.

## Converting success to an Optional

`to_optional() T?` returns the original payload as a present optional, or `none` on error. It deliberately loses the error cause; use it only when that distinction is not needed. It does not flatten the payload or turn faults or cancellation into absence. Save as `optional-price.ms` and run `ms run optional-price.ms`; it prints `true`, then `20`:

<!-- manuscript-example: {"mode":"run","stdout":"true\n20\n"} -->
```manuscript
import Decimal from "@std/math/decimal.ms"

fn successful_price(outcome: Result[Decimal, Error]) Decimal?:
    return outcome.to_optional()

export fn main() Int:
    let absent = successful_price(error(Error("price unavailable")))
    print(absent.is_none())
    let present = successful_price(ok(20d))
    if let value = present:
        print(value)
    return 0
```

To turn absence into an error, use [Optional.ok_or or ok_or_else](../types/optionals.md#converting-absence-to-a-result).

## Discarding a result

A standalone call such as `discount(price: 20d, percent: 10d)` discards both outcomes, and the checker rejects it, including for `Result[Unit, E]`. Handle it with `if let`, `try`, or return it. The syntax `let _ = expression` deliberately discards a result; it is not error handling and should not replace the success and error paths shown above.

The initializer still runs and the outcome is dropped unread. Several `let _` may share a scope. This does not handle an error or stop a fault.

## Converting a domain error to Error

`try` forwards the error type unchanged and never converts one. Translate a domain error with an ordinary function or `map_error`. Save as `discount-error.ms` beside `discount.ms` and run `ms run discount-error.ms`; it reports `percent must be between 0 and 100` and exits with status 1:

<!-- manuscript-example: {"mode":"run","stdout":"percent must be between 0 and 100\n","exit_code":1,"build_files":{"discount.ms":"import Decimal from \"@std/math/decimal.ms\"\n\nexport enum DiscountError:\n    InvalidPrice\n    InvalidPercent\n\nexport fn discount(price: Decimal, percent: Decimal) Decimal!DiscountError:\n    if price < 0d:\n        return error(InvalidPrice)\n    if percent < 0d or percent > 100d:\n        return error(InvalidPercent)\n\n    return ok(price * (1d - percent / 100d))"}} -->
```manuscript
import Decimal from "@std/math/decimal.ms"
import DiscountError, discount from "./discount.ms"

fn discount_error(cause: DiscountError) Error:
    match cause:
        InvalidPrice:
            return Error("price must not be negative", kind: "EINVAL")
        InvalidPercent:
            return Error("percent must be between 0 and 100", kind: "EINVAL")

fn discount_checked(price: Decimal, percent: Decimal) Decimal!:
    return discount(price, percent).map_error(discount_error)

export fn main() Int:
    let outcome = discount_checked(20d, 110d)
    if let value = outcome:
        print(value)
        return 0
    print(outcome.err().message)
    return 1
```

The translator handles every domain case and preserves a useful explanation. `map_error` runs it only on failure; a successful price is unchanged. This is useful at a boundary where application-specific errors meet standard-library operations that return `Error`.

## Compose validation and calculation

Suppose an order form supplies its quantity as text. Parsing can fail before the quantity rule is even checked. Keep these separate steps, then let `try` carry either error to the caller:

Save as `order.ms` and run `ms run order.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"Total: 36\nQuantity must be positive\nEnter a whole number\n"} -->
```manuscript
fn quantity(text: String) Int!:
    let value = try text.parse_int().ok_or(Error("Enter a whole number"))
    if value <= 0:
        return error(Error("Quantity must be positive"))
    return ok(value)

fn order_total(text: String) Int!:
    let count = try quantity(text)
    return ok(count * 12)

fn show_order(text: String) Unit:
    let outcome = order_total(text)
    if let value = outcome:
        print("Total: {value}")
        return
    print(outcome.err().message)

export fn main() Int:
    show_order("3")
    show_order("0")
    show_order("three")
    return 0
```

```text
Total: 36
Quantity must be positive
Enter a whole number
```

`order_total` returns `Int!` for the same reason `quantity` does: it cannot produce a total for every input. It changes the successful value while preserving the failure. `show_order` is the boundary that chooses to print the error and continue with another order. For a command that must stop instead, return a nonzero exit status from `main`.

The corresponding composition is `quantity(text).map(fn count: count * 12)`. Use `map` for a callback returning a plain value; use `and_then` when the next operation itself returns a Result with the same error type. Using `map` with a fallible callback keeps a nested Result rather than removing a layer.

Add context with `wrap_error(context, cause)` from `@std/core.ms`: `error(wrap_error("read config", cause))` reports `read config: <cause message>`, keeps the kind and details, and stores the original message in `details["cause"]`. `join_errors(errors)` combines several errors into one `Error` whose message holds theirs, one per line, with a `count` detail (none when the list is empty).

Use [Optional](../types/optionals.md) for absence and [faults](faults.md) for broken invariants.
