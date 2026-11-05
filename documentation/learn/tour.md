+++
title = "Language tour"
weight = 2
+++

# Language tour

Review an agent’s data flow through complete examples; save each separately as `example.ms`. Manuscript is in alpha, and syntax and APIs may change.

## Print your first line

<!-- manuscript-example: {"mode":"run","filename":"example.ms","stdout":"Hello, Manuscript!\n"} -->
```manuscript {filename="example.ms"}
export fn main() Int:
    print("Hello, Manuscript!")
    return 0
```

```sh
ms run example.ms
```

```text
Hello, Manuscript!
```

- `print` is available without an import; `main` returns the exit status.

## Variables and text

<!-- manuscript-example: {"mode":"test","filename":"example.ms","stdout":"RUN example.ms::unread message count\nPASS example.ms::unread message count\n1 tests, 0 failed\n"} -->
```manuscript {filename="example.ms"}
import expect_equal from "@std/test/test.ms"

test "unread message count":
    let customer = "Sam"
    var unread = 2
    unread += 1
    let message = "{customer}, you have {unread} unread messages."
    let enabled: Bool = true
    try expect_equal(enabled, true)
    try expect_equal(message, "Sam, you have 3 unread messages.")
```

```sh
ms test example.ms
```

```text
RUN example.ms::unread message count
PASS example.ms::unread message count
1 tests, 0 failed
```

- Types are inferred; use `var` when a binding must change.

## Lists, maps, and sets

<!-- manuscript-example: {"mode":"test","filename":"example.ms","stdout":"RUN example.ms::collections and lookup\nPASS example.ms::collections and lookup\n1 tests, 0 failed\n"} -->
```manuscript {filename="example.ms"}
import expect_equal from "@std/test/test.ms"

test "collections and lookup":
    var tags = ["docs", "release"]
    tags.append("featured")
    let original = tags.clone()
    tags.append("news")
    try expect_equal(original.length(), 3)
    try expect_equal(tags.length(), 4)

    var visits = {"/help": 12}
    visits.add("/tour", 4)
    try expect_equal(visits.get("/help").get(0), 12)
    try expect_equal(visits.get("/missing").get(0), 0)

    var subscribers = Set[String]()
    subscribers.add("sam@example.com")
    subscribers.add("sam@example.com")
    try expect_equal(subscribers.length(), 1)
```

```sh
ms test example.ms
```

```text
RUN example.ms::collections and lookup
PASS example.ms::collections and lookup
1 tests, 0 failed
```

- Collections have one owner; `.clone()` makes a separate copy.
- A missing map key returns `T?`; use a default or handle absence.

## Conditions and loops

<!-- manuscript-example: {"mode":"test","filename":"example.ms","stdout":"RUN example.ms::free shipping for orders of at least 40\nPASS example.ms::free shipping for orders of at least 40\n1 tests, 0 failed\n"} -->
```manuscript {filename="example.ms"}
import expect_equal from "@std/test/test.ms"

test "free shipping for orders of at least 40":
    let prices = [12, 8, 25]
    var total = 0
    for price in prices:
        total += price

    var shipping = 5
    if total >= 40:
        shipping = 0
    try expect_equal(total + shipping, 45)
```

```sh
ms test example.ms
```

```text
RUN example.ms::free shipping for orders of at least 40
PASS example.ms::free shipping for orders of at least 40
1 tests, 0 failed
```

- `break` stops a loop; `continue` starts its next iteration.

## Count iterations

<!-- manuscript-example: {"mode":"test","filename":"example.ms","stdout":"RUN example.ms::count five iterations\nPASS example.ms::count five iterations\n1 tests, 0 failed\n"} -->
```manuscript {filename="example.ms"}
import expect_equal from "@std/test/test.ms"

test "count five iterations":
    var total = 0
    for index in 0..5:
        total += index
    try expect_equal(total, 10)
```

```sh
ms test example.ms
```

```text
RUN example.ms::count five iterations
PASS example.ms::count five iterations
1 tests, 0 failed
```

- `0..5` includes 0 and excludes 5.

## Functions

<!-- manuscript-example: {"mode":"test","filename":"example.ms","stdout":"RUN example.ms::greet by name\nPASS example.ms::greet by name\n1 tests, 0 failed\n"} -->
```manuscript {filename="example.ms"}
import expect_equal from "@std/test/test.ms"

fn greeting(name: String = "world") String:
    return "Hello, {name}!"

test "greet by name":
    try expect_equal(greeting("Sam"), "Hello, Sam!")
    try expect_equal(greeting(), "Hello, world!")
```

```sh
ms test example.ms
```

```text
RUN example.ms::greet by name
PASS example.ms::greet by name
1 tests, 0 failed
```

- Parameters and results are typed; defaults can be omitted.

## Types for application data

<!-- manuscript-example: {"mode":"test","filename":"example.ms","stdout":"RUN example.ms::publish a help page\nPASS example.ms::publish a help page\n1 tests, 0 failed\n"} -->
```manuscript {filename="example.ms"}
import expect_equal from "@std/test/test.ms"

type Todo:
    title: String
    completed: Bool = false

enum Status:
    Draft
    Published(url: String)

fn status_label(status: Status) String:
    match status:
        Draft:
            return "Not published"
        Published(url):
            return "Published at {url}"

test "publish a help page":
    var todo = Todo("Update the help page")
    todo.completed = true
    let backup = todo.clone()
    todo.title = "Update the contact page"
    let label = status_label(Status.Published("/help"))
    try expect_equal(backup.title, "Update the help page")
    try expect_equal(backup.completed, true)
    try expect_equal(label, "Published at /help")
```

```sh
ms test example.ms
```

```text
RUN example.ms::publish a help page
PASS example.ms::publish a help page
1 tests, 0 failed
```

- Records group fields; enums name variants checked by exhaustive `match`.

## Expected errors

<!-- manuscript-example: {"mode":"test","filename":"example.ms","stdout":"RUN example.ms::validate quantity\nPASS example.ms::validate quantity\n1 tests, 0 failed\n"} -->
```manuscript {filename="example.ms"}
import expect_equal, expect_error from "@std/test/test.ms"

fn quantity(value: Int) Int!:
    if value <= 0:
        return error(Error("quantity must be positive"))
    return ok(value)

test "validate quantity":
    try expect_equal(try quantity(3), 3)
    let cause = try expect_error(quantity(0))
    try expect_equal(cause.message, "quantity must be positive")
```

```sh
ms test example.ms
```

```text
RUN example.ms::validate quantity
PASS example.ms::validate quantity
1 tests, 0 failed
```

- `T!` returns a value or an expected error; `try` forwards the error.

## Function types and captures {#closures-and-shared-data}

<!-- manuscript-example: {"mode":"test","filename":"example.ms","stdout":"RUN example.ms::a callback borrows a prepared value\nPASS example.ms::a callback borrows a prepared value\n1 tests, 0 failed\n"} -->
```manuscript {filename="example.ms"}
import expect_equal from "@std/test/test.ms"

fn apply(value: Int, transform: fn(Int) Int) Int:
    return transform(value)

test "a callback borrows a prepared value":
    var offset = 1
    offset += 1
    let adjust = fn(value: Int) Int:
        return value + offset
    try expect_equal(apply(10, adjust), 12)
```

```sh
ms test example.ms
```

```text
RUN example.ms::a callback borrows a prepared value
PASS example.ms::a callback borrows a prepared value
1 tests, 0 failed
```

- A borrowed capture keeps its owner available and unchanged while used.

## Pipe flows

<!-- manuscript-example: {"mode":"test","filename":"example.ms","stdout":"RUN example.ms::pipe flow\nPASS example.ms::pipe flow\n1 tests, 0 failed\n"} -->
```manuscript {filename="example.ms"}
import expect_equal from "@std/test/test.ms"

type Reading:
    celsius: Int

fn parse_reading(text: String) Reading!:
    let celsius = try text.trim().parse_int().ok_or()
    return ok(Reading(celsius))

fn to_fahrenheit(reading: Reading) Int:
    return reading.celsius * 9 / 5 + 32

fn fahrenheit(text: String) Int!:
    let value = try parse_reading(text) | to_fahrenheit
    return ok(value)

test "pipe flow":
    try expect_equal(try fahrenheit(" 100 "), 212)
```

```sh
ms test example.ms
```

```text
RUN example.ms::pipe flow
PASS example.ms::pipe flow
1 tests, 0 failed
```

- `|` passes a value to the next call; `try` propagates an error.

## Behavior on types

<!-- manuscript-example: {"mode":"test","filename":"example.ms","stdout":"RUN example.ms::counter behavior\nPASS example.ms::counter behavior\n1 tests, 0 failed\n"} -->
```manuscript {filename="example.ms"}
import expect_equal from "@std/test/test.ms"

interface Increment:
    var fn increment() Unit

type Counter:
    value: Int

impl Increment for Counter:
    var fn increment() Unit:
        self.value = self.value + 1

fn reset(var counter: Counter) Unit:
    counter.value = 0

test "counter behavior":
    var counter = Counter(0)
    counter.increment()
    try expect_equal(counter.value, 1)
    reset(var counter)
    try expect_equal(counter.value, 0)
```

```sh
ms test example.ms
```

```text
RUN example.ms::counter behavior
PASS example.ms::counter behavior
1 tests, 0 failed
```

- `var` appears at the parameter and call when a function mutates its argument.

## Own methods

<!-- manuscript-example: {"mode":"test","filename":"example.ms","stdout":"RUN example.ms::own methods\nPASS example.ms::own methods\n1 tests, 0 failed\n"} -->
```manuscript {filename="example.ms"}
import expect_equal from "@std/test/test.ms"

type Counter:
    value: Int

impl Counter:
    var fn increment() Unit:
        self.value = self.value + 1

test "own methods":
    var counter = Counter(0)
    counter.increment()
    try expect_equal(counter.value, 1)
```

```sh
ms test example.ms
```

```text
RUN example.ms::own methods
PASS example.ms::own methods
1 tests, 0 failed
```

- Use an interface when callers need a shared operation contract.

## Modules

<!-- manuscript-example: {"mode":"test","filename":"example.ms","stdout":"RUN example.ms::import a parser\nPASS example.ms::import a parser\n1 tests, 0 failed\n"} -->
```manuscript {filename="example.ms"}
import parse from "@std/data/json.ms"
import expect_equal from "@std/test/test.ms"

test "import a parser":
    let count = try parse[Int]("3")
    try expect_equal(count, 3)
```

```sh
ms test example.ms
```

```text
RUN example.ms::import a parser
PASS example.ms::import a parser
1 tests, 0 failed
```

- Import standard APIs from `@std/…`; local modules use [relative paths](../core-language/modules/declarations.md).

## Files and cleanup

Create `notes.txt` containing exactly `hello` (five bytes), then save this as `example.ms`.

<!-- manuscript-example: {"mode":"test","filename":"example.ms","files":{"notes.txt":"hello"},"stdout":"RUN example.ms::read a file in its owning scope\nPASS example.ms::read a file in its owning scope\n1 tests, 0 failed\n"} -->
```manuscript {filename="example.ms"}
import open from "@std/os/fs.ms"
import expect_equal from "@std/test/test.ms"

test "read a file in its owning scope":
    let file = try open("notes.txt", flags: "r", mode: 0)
    let contents = try file.read_file(max_bytes: 1048576)
    try expect_equal(contents.length(), 5)
```

```sh
ms test example.ms
```

```text
RUN example.ms::read a file in its owning scope
PASS example.ms::read a file in its owning scope
1 tests, 0 failed
```

- Scope-end drop closes the file, including on early return; handle delivery with explicit flush when writing.

<span id="a-few-compiler-errors-to-recognize"></span>

Next: [testing](testing.md), [task recipes](common-tasks.md), [diagnostics](../developer-tooling/source/diagnostics.md), [language reference](../core-language/_index.md).
