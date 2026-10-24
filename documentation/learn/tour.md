+++
title = "Language tour"
weight = 2
+++

# Language tour

Short examples in order, after [your first program](getting-started.md). Indentation defines blocks; `#` starts a comment. Fragments belong inside a function or test.

## Print your first line

Save this complete program as `hello.ms` and run `ms run hello.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"Hello, Manuscript!\n"} -->
```manuscript
from "@std/io.ms" import stdout

export def main() -> Int:
    if stdout().write("Hello, Manuscript!\n").is_error():
        return 1
    return 0
```

`main` returns the exit status. `is_error()` tests the write's `Result` (see [expected errors](#expected-errors)).

Complete examples below use `test` blocks: save as `example.ms` and run `ms test example.ms`. `try expect_equal(actual, expected)` fails the test on a mismatch ([testing](testing.md)).

## Variables and text

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
from "@std/testing.ms" import expect_equal

test "unread message count":
    let customer = "Sam"
    var unread = 2
    unread += 1
    let message = f"{customer}, you have {unread} unread messages."
    let enabled: Bool = True
    try expect_equal(enabled, True)
    try expect_equal(message, "Sam, you have 3 unread messages.")
```

- `let` fixes the binding; `var` allows reassignment. Types are inferred unless annotated.
- Basic types: `Int`, `Float`, `Bool`, `String`. `{expression}` interpolates into strings.

## Lists, maps, and sets

```manuscript
var tags = ["docs", "release"]
tags.append("featured")
let original = tags.clone()
tags.append("news")
# original still has three tags.

var visits = {"/help": 12}
visits.add("/tour", 4)
var subscribers = Set[String]()
subscribers.add("sam@example.com")

if let count = visits.get("/help"):
    let label = f"{count} visits"
else:
    let label = "No visits yet"
```

- List, Map, and Set need no import. Updates mutate in place.
- Collections have one owner; `.clone()` makes a deep copy. Use `var` to mutate a collection.
- Lookup returns an `Optional` (`some(value)` or `none`); `if let` binds a present value and `else` handles absence.

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

`if` branches; `for` visits items; `while` repeats on a condition; `break` and `continue` control loops.

Count with `range`:

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
from "@std/collections.ms" import range
from "@std/testing.ms" import expect_equal

test "count five iterations":
    var total = 0
    for index in range(0, 5):
        total += index
    try expect_equal(total, 10)
```

`range(0, 5)` visits 0 through 4. For other steps see [counting loops](../core-language/control-flow/loops.md#counting-loops).

## Functions

```manuscript
def greeting(name: String = "world") -> String:
    return f"Hello, {name}!"

def line_total(price: Int, quantity: Int) -> Int:
    return price * quantity

let welcome = greeting("Sam")
let default_welcome = greeting()  # "Hello, world!"
let subtotal = line_total(12, 3)
```

Parameters and returns are typed. Pass arguments by position or label; defaults can be omitted. `Unit` means no result.

Functions are values:

```manuscript

let prices = [12, 8, 25]
let discounted = prices.map(lambda (value: Int) -> Int:
    return value - 2
)
let affordable = discounted.filter(lambda (value: Int) -> Bool:
    return value <= 10
)
# affordable contains [10, 6]; prices is unchanged.
```

## Types for application data

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
from "@std/testing.ms" import expect_equal

type Todo:
    title: String
    completed: Bool = False

type Status:
    case Draft
    case Published(url: String)

def status_label(status: Status) -> String:
    match status:
        case Draft:
            return "Not published"
        case Published(url):
            return f"Published at {url}"

test "publish a help page":
    var todo = Todo("Update the help page")
    todo.completed = True
    let backup = todo.clone()
    todo.title = "Update the contact page"
    let label = status_label(Status.Published("/help"))
    try expect_equal(backup.title, "Update the help page")
    try expect_equal(backup.completed, True)
    try expect_equal(label, "Published at /help")
```

- Records group named fields; omitted fields use defaults, and changing a field needs a `var` binding.
- Alternatives list cases; `match` must handle every case.
- Types are nominal: identical fields do not make two types equal.

## Expected errors

```manuscript
type QuantityError:
    case MustBePositive

def quantity(value: Int) -> Result[Int, QuantityError]:
    if value <= 0:
        return error(QuantityError.MustBePositive)
    return ok(value)

def order_total(count: Int) -> Result[Int, QuantityError]:
    let valid_count = try quantity(count)
    return ok(valid_count * 12)
```

- `Result` is `ok(value)` or `error(cause)`; `try` unwraps success or returns the error.
- Use one error type or the common `Error` boundary. Otherwise handle outcomes with `if let`, `get(default)`, or `is_error()` and `err()`; see [error compatibility](../core-language/errors/propagation.md#error-compatibility).

## Modules

Each `.ms` file is a module; `export` what others need.

`pricing.ms`:

```manuscript
export let UNIT_PRICE = 12

export def line_total(quantity: Int) -> Int:
    return UNIT_PRICE * quantity
```

In another file in the same directory:

```manuscript
from "./pricing.ms" import line_total

export def checkout_total() -> Int:
    return line_total(quantity: 3)
```

Module-level `let` is a constant used without `()`. Import standard APIs from `@std/…` and local code by relative path ([module rules](../core-language/modules/declarations.md)).

## Closures and shared data

```manuscript

var subject = "Weekly update"
let headline = lambda () -> String:
    return subject
subject = "Launch announcement"
# headline() returns "Weekly update".

var tags = ["docs"]
let tag_count = lambda () -> Int:
    return tags.length()
tags.append("release")
# tag_count() returns 2.
```

Non-escaping closures borrow their captures; escaping closures own them. Borrowed captures cannot be changed while the closure still uses them. See [closure examples](../core-language/functions/function-values-and-closures.md#snapshot-captures).

## Pipe flows

`|` passes a value to the next step, so a sequence of calls reads top to bottom. `try` inside a flow unwraps a `Result` and returns early on error:

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
from "@std/testing.ms" import expect_equal

type Reading:
    celsius: Int

def parse_reading(text: String) -> Result[Reading, Error]:
    let celsius = try text.trim().parse_int().ok_or()
    return ok(Reading(celsius))

def to_fahrenheit(reading: Reading) -> Int:
    return reading.celsius * 9 / 5 + 32

def fahrenheit(text: String) -> Result[Int, Error]:
    let value = try parse_reading(text) | to_fahrenheit
    return ok(value)

test "pipe flow":
    try expect_equal(try fahrenheit(" 100 "), 212)
```

`x | f` is `f(x)`; `x | .m()` is `x.m()`. See [pipe flows](../core-language/basics/expressions.md#pipe-flows).

## Behavior on types

Methods live in `impl` blocks, never inside the `type`. Declare an `interface`, then `impl Interface for Type:`; `self` is the receiver:

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
from "@std/testing.ms" import expect_equal

interface Increment:
    var def increment() -> Unit

type Counter:
    value: Int

impl Increment for Counter:
    var def increment() -> Unit:
        self.value = self.value + 1

def reset(var counter: Counter) -> Unit:
    counter.value = 0

test "counter behavior":
    var counter = Counter(0)
    counter.increment()
    try expect_equal(counter.value, 1)
    reset(var counter)
    try expect_equal(counter.value, 0)
```

A type's own methods go in `impl Counter:`, without an interface:

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
from "@std/testing.ms" import expect_equal

type Counter:
    value: Int

impl Counter:
    var def increment() -> Unit:
        self.value = self.value + 1

test "own methods":
    var counter = Counter(0)
    counter.increment()
    try expect_equal(counter.value, 1)
```

Use an interface when callers should depend on behavior rather than on the type. Free functions are called as `reset(counter)`. See [interfaces and implementations](../core-language/types/contracts.md#explicit-implementations).

## Files and cleanup

```manuscript
from "@std/fs.ms" import filesystem, FileSystemError

def copy_notes() -> Result[Unit, FileSystemError]:
    with try filesystem().open("notes.txt", flags: "r", mode: 0) as source:
        let contents = try source.read_file(max_bytes: 1048576)
        try filesystem().write_file_bytes(path: "backup.txt", data: contents, replace: True)
    return ok(())
```

`with` closes the file at block end, even on early return. Closures do not keep it open; see [resource captures](../core-language/functions/function-values-and-closures.md#resource-captures).

## A few compiler errors to recognize

These are intentionally rejected:

```manuscript
let count = 2
count = 3                 # Use var for reassignment.
let mixed = [1, "two"]    # List elements need a common type.
line_total(12)            # Supply the required quantity.
```

Next: [testing](testing.md), [task recipes](common-tasks.md), the [language reference](../core-language/_index.md), and the [API reference](../standard-library/reference/_index.md).
