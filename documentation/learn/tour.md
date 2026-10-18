+++
title = "Language tour"
weight = 2
+++

# Language tour

Start with [a running program](getting-started.md). Read these examples in order; local statements go inside a function or test. Imports and declarations go at the top of the file. Indentation defines blocks, and `#` starts a comment.

## Print your first line

Save this complete program as `hello.ms` and run `ms run hello.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"Hello, Manuscript!\n"} -->
```manuscript
import stdout from "@std/io.ms"

export fn main() -> Int:
    if stdout().write("Hello, Manuscript!\n".to_bytes()).is_error():
        return 1
    return 0
```

`main` returns the exit status: 0 for success, 1 for a failed write.
`is_error()` tests whether the write failed; the [expected errors](#expected-errors)
section explains `Result` in more detail. The import selects the output API.

The complete examples below use `test` blocks. Save one as `example.ms` and run
`ms test example.ms`. `try expect_equal(actual, expected)` checks a value and
fails the test if it differs. This lets you try the language without adding
output code to every example; [test your code](testing.md) explains the helpers.
Other blocks are fragments to place inside a function or test, unless they
declare a type, function, or import.

## Variables and text

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
import expect_equal from "@std/testing.ms"

test "unread message count":
    let customer = "Sam"
    var unread = 2
    unread += 1
    let message = "{customer}, you have {unread} unread messages."
    let enabled: Bool = true
    try expect_equal(enabled, true)
    try expect_equal(message, "Sam, you have 3 unread messages.")
```

`let` keeps the same binding; `var` allows reassignment. Local types are inferred unless you write an annotation. Use `Int` for whole numbers, `Float` for decimals, `Bool` for true or false, and `String` for text. `{expression}` inserts a value into a string.

## Lists, maps, and sets

```manuscript
let tags = ["docs", "release"]
tags.append("featured")
let original = tags.clone()
tags.append("news")
# original still has three tags.

let visits = {"/help": 12}
visits.add(key: "/tour", value: 4)
let subscribers = Set[String]()
subscribers.add("sam@example.com")

if let count = visits.get("/help"):
    let label = "{count} visits"
else:
    let label = "No visits yet"
```

List, Map, and Set are available without imports. Lists preserve order, maps look up values by key, and sets keep distinct values. Updates mutate the collection. Assignment shares the same collection; `.clone()` makes a shallow copy. Lookup returns an `Optional`: `some(value)` or `none`. `if let` binds a present value inside its block; `else` handles absence.

## Conditions and loops

```manuscript

let prices = [12, 8, 25]
var total = 0
for price in prices:
    total += price

var shipping = 5
if total >= 40:
    shipping = 0
let checkout_total = total + shipping
```

`if` chooses a branch. `for` visits each item; `while` repeats while a condition is true. Use `break` to stop a loop or `continue` to skip an iteration.

To repeat a task five times without building a collection, count with `while`:

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
import range from "@std/collections.ms"
import expect_equal from "@std/testing.ms"

test "count five iterations":
    var total = 0
    for index in range(0, 5):
        total += index
    try expect_equal(total, 10)
```

The index visits 0 through 4, and `total += index` is shorthand for `total = total + index`. A `while` loop with its own counter handles other steps; see [counting loops](../core-language/control-flow/loops.md#counting-loops).

## Functions

```manuscript
fn greeting(name: String = "world") -> String:
    return "Hello, {name}!"

fn line_total(price: Int, quantity: Int) -> Int:
    return price * quantity

let welcome = greeting("Sam")
let default_welcome = greeting()  # "Hello, world!"
let subtotal = line_total(12, 3)
```

Functions declare parameter and return types. Call with positional arguments or add labels for clarity. A parameter with a default can be omitted; other parameters are required. Use `Unit` when a function has no result to return.

Pass functions to transform collections:

```manuscript

let prices = [12, 8, 25]
let discounted = prices.map(transform: fn(value: Int) -> Int:
    return value - 2
)
let affordable = discounted.filter(predicate: fn(value: Int) -> Bool:
    return value <= 10
)
# affordable contains [10, 6]; prices is unchanged.
```

## Types for application data

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
import expect_equal from "@std/testing.ms"

type Todo:
    title: String
    completed: Bool = false

type Status:
    case Draft
    case Published(url: String)

fn status_label(status: Status) -> String:
    match status:
        Draft:
            return "Not published"
        Published(url):
            return "Published at {url}"

test "publish a help page":
    let todo = Todo(title: "Update the help page")
    todo.completed = true
    let backup = todo.clone()
    todo.title = "Update the contact page"
    let label = status_label(Status.Published("/help"))
    try expect_equal(backup.title, "Update the help page")
    try expect_equal(backup.completed, true)
    try expect_equal(label, "Published at /help")
```

Records group named fields. Omitted fields use their declared defaults. Fields can change even when the binding uses `let`. Alternatives describe a choice of cases; `match` handles every case. A type's name identifies it, so two record declarations with the same fields remain distinct types.

## Expected errors

```manuscript
type QuantityError:
    case MustBePositive

fn quantity(value: Int) -> Result[Int, QuantityError]:
    if value <= 0:
        return error(QuantityError.MustBePositive)
    return ok(value)

fn order_total(count: Int) -> Result[Int, QuantityError]:
    let valid_count = try quantity(count)
    return ok(valid_count * 12)
```

A `Result` holds `ok(value: value)` or `error(cause)`. `try` unwraps success and returns an error to the caller. Use the same error type, or the common `Error` boundary for errors implementing that interface. Use `if let`, `unwrap_or`, or `is_error()` with `unwrap_error()` to handle an outcome yourself instead of propagating it; see [error compatibility](../core-language/errors/propagation.md#error-compatibility).

## Modules

Each `.ms` file is a module. Export declarations other files need.

`pricing.ms`:

```manuscript
export let UNIT_PRICE = 12

export fn line_total(quantity: Int) -> Int:
    return UNIT_PRICE * quantity
```

In another file in the same directory:

```manuscript
import line_total from "./pricing.ms"

export fn checkout_total() -> Int:
    return line_total(quantity: 3)
```

A module-level `let` declares a constant; use its name without `()`. Collection constants create fresh storage on each use. Import standard APIs from `@std/…`, and local code with a relative path. [Module rules](../core-language/modules/declarations.md) cover grouped imports and visibility.

## Closures and shared data

```manuscript

var subject = "Weekly update"
let headline = fn() -> String:
    return subject
subject = "Launch announcement"
# headline() returns "Weekly update".

let tags = ["docs"]
let tag_count = fn() -> Int:
    return tags.length()
tags.append("release")
# tag_count() returns 2.
```

A closure remembers each binding's value when created. Reassigning a local variable does not change that value. Capturing a collection or record keeps the same object, so later mutations are visible. See [closure examples](../core-language/functions/function-values-and-closures.md#snapshot-captures).

## Behavior on types

Methods live in `impl` blocks, never inside the `type`. Declare an interface when callers should depend on behavior, then implement it with `impl Interface for Type:`. The method's `self` is its receiver:

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
import expect_equal from "@std/testing.ms"

interface Increment:
    fn increment() -> Unit

type Counter:
    value: Int

impl Increment for Counter:
    fn increment() -> Unit:
        self.value = self.value + 1

fn reset(counter: Counter) -> Unit:
    counter.value = 0

test "counter behavior":
    let counter = Counter(0)
    counter.increment()
    try expect_equal(counter.value, 1)
    reset(counter)
    try expect_equal(counter.value, 0)
```

A type's own methods go in `impl Counter:`, without an interface:

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
import expect_equal from "@std/testing.ms"

type Counter:
    value: Int

impl Counter:
    fn increment() -> Unit:
        self.value = self.value + 1

test "own methods":
    let counter = Counter(0)
    counter.increment()
    try expect_equal(counter.value, 1)
```

Use an interface when callers should depend on behavior rather than on the type. A free function is still called as `reset(counter)`, not `counter.reset()`. Interface operations can be called on a concrete receiver when exactly one visible interface implementation supplies that name. See [interfaces and implementations](../core-language/types/contracts.md#explicit-implementations) for signatures, visibility, and selecting an interface view when names are ambiguous.

## Files and cleanup

```manuscript
import {filesystem, FileSystemError} from "@std/fs.ms"

fn copy_notes() -> Result[Unit, FileSystemError]:
    with source = try filesystem().open(path: "notes.txt", flags: "r", mode: 0):
        let contents = try source.read_file(max_bytes: 1048576)
        try filesystem().write_file(path: "backup.txt", data: contents, replace: true)
    return ok(unit)
```

`with` closes the file when the block ends, including an early return. A closure that captures the file keeps a reference but does not keep it open. Read it inside the block, or open a new file inside the callback. [Resource captures](../core-language/functions/function-values-and-closures.md#resource-captures) shows a complete example.

## A few compiler errors to recognize

These fragments are intentionally rejected:

```manuscript
let count = 2
count = 3                 # Use var for reassignment.
let mixed = [1, "two"]    # List elements need a common type.
line_total(12)            # Supply the required quantity.
```

Keep these cases separate from runnable examples. Next, [test your code](testing.md), then put these ideas to work in the
[task recipes](common-tasks.md). Use the [language reference](../core-language/_index.md)
when you need an exact rule, or the [API reference](../standard-library/reference/_index.md)
when you need a particular function.
