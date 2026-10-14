+++
title = "A language tour"
weight = 2
+++

# A language tour

Start with [a running program](getting-started.md). Read these examples in order; local statements go inside a function or test. Imports and declarations go at the top of the file. Indentation defines blocks, and `#` starts a comment.

## Print your first line

Save this complete program as `hello.ms` and run `ms run hello.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"Hello, Manuscript!\n"} -->
```manuscript
import stdout from "@std/io.ms"

fn say(text: String) -> Result[Unit, Error]:
    try stdout().write("{text}\n".to_bytes())
    return stdout().flush()

export fn main() -> Int:
    match say("Hello, Manuscript!"):
        ok(_): return 0
        error(_): return 1
```

`main` returns the exit status: 0 for success, 1 for a failed write or flush. `try` forwards an error to the caller; the [expected errors](#expected-errors) section explains that pattern. There is no built-in `print` function. See [common tasks](common-tasks.md) for files, input, arguments, and HTTP, and [testing](testing.md) for the `panic` checks used below.

## Variables and text

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
import panic from "@std/faults.ms"

test "unread message count":
    let customer = "Sam"
    var unread = 2
    unread = unread + 1
    let message = "{customer}, you have {unread} unread messages."
    let enabled: Bool = true
    if not (enabled and message == "Sam, you have 3 unread messages."):
        return panic(message: "Unexpected message")
```

`let` keeps the same binding; `var` allows reassignment. Local types are inferred unless you write an annotation. Use `Int` for whole numbers, `Float` for decimals, `Bool` for true or false, and `String` for text. `{expression}` inserts a value into a string.

## Lists, maps, and sets

```manuscript
let tags = ["docs", "release"]
tags.append("featured")
let original = tags.clone()
tags.append("news")
# original still has three tags.

let visits = Map[String, Int]()
visits.add(key: "/help", value: 12)
let subscribers = Set[String]()
subscribers.add("sam@example.com")

match visits.get("/help"):
    some(count):
        let label = "{count} visits"
    none:
        let label = "No visits yet"
```

List, Map, and Set are available without imports. Lists preserve order, maps look up values by key, and sets keep distinct values. Updates mutate the collection. Assignment shares the same collection; `.clone()` makes a shallow copy. Lookup returns an `Optional`: `some(value)` or `none`.

## Conditions and loops

```manuscript

let prices = [12, 8, 25]
var total = 0
for price in prices:
    total = total + price

var shipping = 5
if total >= 40:
    shipping = 0
let checkout_total = total + shipping
```

`if` chooses a branch. `for` visits each item; `while` repeats while a condition is true. Use `break` to stop a loop or `continue` to skip an iteration.

To repeat a task five times without building a collection, count with `while`:

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
import panic from "@std/faults.ms"

test "count five iterations":
    var index = 0
    var total = 0
    while index < 5:
        total = total + index
        index = index + 1
    if total != 10:
        return panic("Expected 10, got {total}")
```

The index visits 0 through 4. Update the counter on every path that continues the loop. To build a list of integers, handle `range(start: 0, end: 5, step: 1)`'s `Result` before iterating; see [counting loops](../core-language/control-flow/loops.md#counting-loops).

## Functions

```manuscript
fn greeting(name: String) -> String:
    return "Hello, {name}!"

fn line_total(price: Int, quantity: Int) -> Int:
    return price * quantity

let welcome = greeting("Sam")
let subtotal = line_total(12, 3)
```

Functions declare parameter and return types. Call with positional arguments or add labels for clarity. Use `Unit` when a function has no result to return.

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
import panic from "@std/faults.ms"

type Todo:
    title: String
    completed: Bool

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
    let todo = Todo(title: "Update the help page", completed: false)
    todo.completed = true
    let backup = todo.clone()
    todo.title = "Update the contact page"
    let label = status_label(Status.Published("/help"))
    if not (backup.title == "Update the help page" and backup.completed and label == "Published at /help"):
        return panic(message: "Unexpected page data")
```

Records group named fields. Fields can change even when the binding uses `let`. Alternatives describe a choice of cases; `match` handles every case. A type's name identifies it, so two record declarations with the same fields remain distinct types.

## Behavior on types

Declare an interface for user-defined methods, then implement it with `impl Interface for Type:`. The method's `self` is its receiver:

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
import panic from "@std/faults.ms"

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
    if counter.value != 1:
        return panic("Expected 1, got {counter.value}")
    reset(counter)
    if counter.value != 0:
        return panic("Expected 0, got {counter.value}")
```

Manuscript has no user-defined inherent methods: `impl Counter:` is unsupported. A free function is called as `reset(counter)`, not `counter.reset()`. Interface operations can be called on a concrete receiver when exactly one visible interface implementation supplies that name. See [interfaces and implementations](../core-language/types/contracts.md#explicit-implementations) for signatures, visibility, and selecting an interface view when names are ambiguous.

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

A `Result` holds `ok(value: value)` or `error(cause)`. `try` unwraps success and returns an error to the caller. Use the same error type, or the common `Error` boundary for errors implementing that interface. Use `match` when you want to handle both outcomes yourself; see [error compatibility](../core-language/errors/propagation.md#error-compatibility).

## Modules

Each `.ms` file is a module. Export declarations other files need.

`pricing.ms`:

```manuscript
export fn line_total(price: Int, quantity: Int) -> Int:
    return price * quantity
```

In another file in the same directory:

```manuscript
import line_total from "./pricing.ms"

export fn checkout_total() -> Int:
    return line_total(price: 12, quantity: 3)
```

Import standard APIs from `@std/…`, and local code with a relative path. [Module rules](../core-language/modules/declarations.md) cover grouped imports and visibility.

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

## Files and cleanup

```manuscript
import {filesystem, FileSystemError} from "@std/fs.ms"

fn copy_notes() -> Result[Unit, FileSystemError]:
    with source = try filesystem().open(path: "notes.txt", flags: "r", mode: 0):
        let contents = try source.read_file(max_bytes: 1048576)
        let written = try filesystem().write_file(path: "backup.txt", data: contents, replace: true)
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

Keep these cases separate from runnable examples. Continue with the [language guide](../core-language/_index.md) or find an API in the [API reference](../standard-library/reference/_index.md).
