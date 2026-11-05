+++
title = "Language tour"
weight = 2
+++

# Language tour

This tour introduces the pieces you need to write a small program: name values,
transform collections, define functions and data, handle missing values and errors,
and organize work into modules. Start after [your first program](getting-started.md).
You do not need to memorize every rule here; each section links to the chapter that
explains the choices in detail.

The examples build on familiar tasks such as preparing a message, totaling an order,
and publishing a page. Each complete program can replace `example.ms`; run it with
`ms run example.ms`. Examples marked as fragments illustrate part of a larger file.
Indentation defines blocks, four spaces indent a body, and `//` starts a comment.

## Print your first line

Save this complete program as `hello.ms` and run `ms run hello.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"Hello, Manuscript!\n"} -->
```manuscript
export fn main() Int:
    print("Hello, Manuscript!")
    return 0
```

Output:

```text
Hello, Manuscript!
```

`main` returns the exit status. `print` is in the prelude: it writes a value as text followed by a newline and returns `Unit`. Use `stdout()` from `@std/io/io.ms` for text without an added newline, or `stdout_bytes()` for bytes.

Some later examples use `test` blocks to check a rule directly. For those examples,
save the complete file as `example.ms` and run `ms test example.ms`.
`try expect_equal(actual, expected)` fails the test on a mismatch; the
[testing chapter](testing.md) develops that workflow.

## Variables and text

A message needs a recipient and a count. Name the recipient with `let` because this
program does not replace it. Use `var` for the count because receiving a message
changes it:

<!-- manuscript-example: {"mode":"run","stdout":"Sam, you have 3 unread messages.\n"} -->
```manuscript
export fn main() Int:
    let customer = "Sam"
    var unread = 2
    unread += 1
    let message = "{customer}, you have {unread} unread messages."
    print(message)
    return 0
```

```text
Sam, you have 3 unread messages.
```

The compiler infers `String` for `customer` and `Int` for `unread` from their initial
values. An annotation such as `let unread: Int = 2` makes the type explicit; it does
not change the value. Once a binding has a type, assigning a value of another type
is an error. `let` prevents reassignment, while `var` permits it.

Inside a string, `{expression}` inserts the expression's text. You can interpolate
an arithmetic expression as well as a name. Try replacing `{unread}` with
`{unread + 1}`: the displayed count changes, but the `unread` variable does not.

The basic types include `Int`, `Float`, `Bool`, and `String`. `Int` is `Int64` and
`Float` is `Float64`; select `Int8`, `Int16`, `Int32`, or `Float32` when the width
matters. Numeric conversions are explicit, and narrowing integer conversions
return an optional value because the number might not fit. Continue with
[bindings](../core-language/basics/bindings.md),
[numbers](../core-language/basics/numbers-and-booleans.md), and
[text](../core-language/basics/text-and-bytes.md).

## Lists, maps, and sets

A list keeps values in order. A map associates keys with values, and a set keeps
only distinct values. All three types are available without imports:

<!-- manuscript-example: {"mode":"run","stdout":"Tags: 3\nHelp visits: 12\nMissing visits: 0\nSubscribers: 1\n"} -->
```manuscript
export fn main() Int:
    var tags = ["docs", "release"]
    tags.append("featured")
    print("Tags: {tags.length()}")

    var visits = {"/help": 12}
    visits.add("/tour", 4)
    print("Help visits: {visits.get("/help").get(0)}")
    print("Missing visits: {visits.get("/missing").get(0)}")

    var subscribers = Set[String]()
    subscribers.add("sam@example.com")
    subscribers.add("sam@example.com")
    print("Subscribers: {subscribers.length()}")
    return 0
```

```text
Tags: 3
Help visits: 12
Missing visits: 0
Subscribers: 1
```

`tags` has type `List[String]`; `visits` has type `Map[String, Int]`. The type
arguments describe their contents. A list of strings cannot also hold an integer.
The empty set uses `Set[String]()` to tell the compiler which type it will contain.

Each update changes the collection in place, so its binding is `var`. Adding the
same subscriber twice leaves one element. Map lookup can miss: `get(key)` returns
an optional value, and the following `get(0)` chooses zero when it is absent.
That fallback is appropriate for a visit count; use a branch when missing data
needs a different action. See [collections](../core-language/types/collections.md).

### Keep an independent copy

Assignment is not an implicit deep copy. When two versions need to diverge,
write `.clone()` explicitly:

<!-- manuscript-example: {"mode":"run","stdout":"Original: 2, updated: 3\n"} -->
```manuscript
export fn main() Int:
    var tags = ["docs", "release"]
    let original = tags.clone()
    tags.append("news")
    print("Original: {original.length()}, updated: {tags.length()}")
    return 0
```

```text
Original: 2, updated: 3
```

Collections, strings, and records have one owner. Reading through a borrow uses
that owner's data; moving a value transfers ownership. A clone creates independent
data, including nested values. This distinction matters when you keep a snapshot,
return part of a value, or pass data to another function. The
[ownership chapter](../core-language/types/references.md) explains when the compiler
borrows and when it moves, and why an owner cannot change while a borrow is in use.

## Conditions and loops

To total an order, visit each price and add it to an accumulator. Then choose the
shipping charge from the total:

<!-- manuscript-example: {"mode":"run","stdout":"Subtotal: 45, shipping: 0, total: 45\n"} -->
```manuscript
export fn main() Int:
    let prices = [12, 8, 25]
    var total = 0
    for price in prices:
        total += price

    var shipping = 5
    if total >= 40:
        shipping = 0
    print("Subtotal: {total}, shipping: {shipping}, total: {total + shipping}")
    return 0
```

```text
Subtotal: 45, shipping: 0, total: 45
```

`for` binds `price` to each element in order. The accumulator is declared outside
the loop so each iteration updates the same value. `if` takes a Boolean condition;
`>=` compares the total with the free-shipping threshold. Change the last price to
`5` and the subtotal becomes `25`, so the shipping charge remains `5`.

Use `else` for a second branch and `else if` for more conditions. `while` repeats
while its condition is true; `break` leaves a loop and `continue` starts its next
iteration. For counting, the range `0..5` visits 0 through 4:

<!-- manuscript-example: {"mode":"run","stdout":"10\n"} -->
```manuscript
export fn main() Int:
    var total = 0
    for index in 0..5:
        total += index
    print(total)
    return 0
```

```text
10
```

The upper endpoint is excluded. See [counting loops](../core-language/control-flow/loops.md#counting-loops)
for other steps, and [expressions](../core-language/basics/expressions.md) for
operator precedence and evaluation order.

## Functions

When several callers need the same calculation, give it a function. Parameters
name its inputs, and the type after `)` names its result:

<!-- manuscript-example: {"mode":"run","stdout":"Hello, Sam!\nHello, world!\nSubtotal: 36\n"} -->
```manuscript
fn greeting(name: String = "world") String:
    return "Hello, {name}!"

fn line_total(price: Int, quantity: Int) Int:
    return price * quantity

export fn main() Int:
    print(greeting("Sam"))
    print(greeting())
    let subtotal = line_total(price: 12, quantity: 3)
    print("Subtotal: {subtotal}")
    return 0
```

```text
Hello, Sam!
Hello, world!
Subtotal: 36
```

`greeting` uses its default when the caller omits `name`. `line_total` requires both
arguments. Labels such as `quantity:` make the call readable; `line_total(12, 3)`
is the positional form. Each argument must fit the declared parameter type, and
`return` supplies the result. A function returning `Unit` performs work without
producing a useful value. See [declarations and calls](../core-language/functions/declarations-and-calls.md)
for label ordering, default scope, optional omission, and return completeness.

Functions can also be passed as values. A short anonymous function describes a
transformation without giving it a separate name:

<!-- manuscript-example: {"mode":"run","stdout":"10\n6\n"} -->
```manuscript
export fn main() Int:
    let prices = [12, 8, 25]
    let discounted = prices.map(fn value: value - 2)
    let affordable = discounted.filter(fn value: value <= 10)
    for price in affordable:
        print(price)
    return 0
```

```text
10
6
```

`map` produces a list by applying the function to each item. `filter` keeps items
whose predicate returns `true`. These operations produce new lists; they do not
mutate `prices`. Later in the tour, [function types and captures](#closures-and-shared-data)
show how callbacks use surrounding values.

## Types for application data

A record gives related fields one name. An enum represents a choice among distinct
cases, with data attached only where it is needed. A page can be a draft without a
URL, or published with one:

<!-- manuscript-example: {"mode":"run","stdout":"Update the help page\nPublished at /help\n"} -->
```manuscript
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

export fn main() Int:
    var todo = Todo("Update the help page")
    todo.completed = true
    let backup = todo.clone()
    todo.title = "Update the contact page"
    print(backup.title)
    print(status_label(Status.Published("/help")))
    return 0
```

```text
Update the help page
Published at /help
```

The `Todo` constructor takes `title` and uses the default `false` for `completed`.
Changing a field requires a `var` binding. The clone preserves the original title
when the working copy changes. Records are nominal: another type with the same
fields is still a different type.

`Status.Published("/help")` constructs a case with its URL. `match` selects the
case and binds its payload to `url`. The case names in the arms are bare names,
not declarations. Every case must be covered, so adding a case also identifies
matches that need updating. Try passing `Status.Draft` instead to take the other
branch. Read more about [records](../core-language/types/records.md),
[enums](../core-language/types/alternatives.md), and
[matching](../core-language/control-flow/pattern-matching.md).

## Optional values

A lookup or conversion can have no value. `Int?` means an integer may be present
or absent; it does not mean a special integer such as zero. Parsing text makes the
difference useful:

<!-- manuscript-example: {"mode":"run","stdout":"Quantity: 3\nEnter a whole number\n"} -->
```manuscript
fn describe_quantity(text: String) String:
    let parsed: Int? = text.parse_int()
    if let quantity = parsed:
        return "Quantity: {quantity}"
    return "Enter a whole number"

export fn main() Int:
    print(describe_quantity("3"))
    print(describe_quantity("three"))
    return 0
```

```text
Quantity: 3
Enter a whole number
```

`if let` enters the body only when the optional contains a value, and binds the
payload to `quantity`. Outside the branch there is no integer to use. Construct an
absent optional with `none`. A plain value becomes present where an optional is
expected, as in `let quantity: Int? = 3`; there is no `some` constructor.
Use `get(default)` when absence has a sensible fallback, as with the visit counts
earlier. A branch is better here because silently treating invalid input as zero
would hide a mistake. See [optional values](../core-language/types/optionals.md)
for wrapping, nested optionals, and optional arguments.

## Expected errors

An optional says that a value is absent. A `Result` also explains why an operation
failed. Use `T!` for `Result[T, Error]`, where `Error` carries a message and a kind.
For a domain with a fixed set of failures, use your own error type: `T!E` is
`Result[T, E]`.

<!-- manuscript-example: {"mode":"run","stdout":"Total: 36\nQuantity must be positive\n"} -->
```manuscript
enum QuantityError:
    MustBePositive

fn quantity(value: Int) Int!QuantityError:
    if value <= 0:
        return error(QuantityError.MustBePositive)
    return ok(value)

fn order_total(count: Int) Int!QuantityError:
    let valid_count = try quantity(count)
    return ok(valid_count * 12)

fn describe_order(count: Int) String:
    if let total = order_total(count):
        return "Total: {total}"
    return "Quantity must be positive"

export fn main() Int:
    print(describe_order(3))
    print(describe_order(0))
    return 0
```

```text
Total: 36
Quantity must be positive
```

`ok(value)` holds a successful result and `error(cause)` holds a failure. In
`order_total`, `try` takes the successful quantity or returns its error immediately.
That works because both functions declare the same error type. The caller uses
`if let` for success and returns a message on failure, keeping the policy about
what to show outside the calculation.

A discarded result would lose that decision. Handle it, propagate it with `try`,
or explicitly choose a fallback when the task permits one. For larger programs,
[Results](../core-language/errors/results.md) and
[propagation](../core-language/errors/propagation.md) explain error translation and
composition; [faults](../core-language/errors/faults.md) distinguish programming
failures from expected errors.

## Modules

As a program grows, separate a reusable calculation from the code that starts the
application. Each `.ms` file is a module. An `export` makes a declaration available
to other modules; declarations without it stay private to the module.

`pricing.ms`:

```manuscript
export let UNIT_PRICE = 12

export fn line_total(quantity: Int) Int:
    return UNIT_PRICE * quantity
```

Save this as `example.ms` in the same directory, then run `ms run example.ms`:

<!-- manuscript-example: {"mode":"run","build_files":{"pricing.ms":"export let UNIT_PRICE = 12\n\nexport fn line_total(quantity: Int) Int:\n    return UNIT_PRICE * quantity\n"},"stdout":"36\n"} -->
```manuscript
import line_total from "./pricing.ms"

export fn main() Int:
    print(line_total(quantity: 3))
    return 0
```

```text
36
```

Module-level `let` is a constant used without `()`. Import standard APIs from `@std/…` and local code by relative path ([module rules](../core-language/modules/declarations.md)).

## Function types and captures {#closures-and-shared-data}

`fn(Int) Int` names a function that takes an `Int` and returns an `Int`. Use `fn` to create a callback:

<!-- manuscript-example: {"mode":"test","stdout":"RUN example.ms::a callback borrows a prepared value\nPASS example.ms::a callback borrows a prepared value\n1 tests, 0 failed\n"} -->
```manuscript
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

Test output:

```text
RUN example.ms::a callback borrows a prepared value
PASS example.ms::a callback borrows a prepared value
1 tests, 0 failed
```

The callback adds the prepared `offset` to the input, so `apply(10, adjust)` returns
`12`. `apply` does not need to know where that offset came from: its parameter only
requires the type `fn(Int) Int`.

A value read from the surrounding scope is a capture. Non-escaping closures borrow
their captures; escaping closures own them. Prepare a borrowed value before making
the closure, because the owner cannot change it while the closure still uses it.
This rule prevents a callback from observing a value while another path mutates
it. See [closure captures](../core-language/functions/function-values-and-closures.md#closure-captures)
for returned callbacks and resource ownership.

## Pipe flows

`|` passes a value to the next step, so a sequence of calls reads top to bottom. `try` inside a flow unwraps a `Result` and returns early on error:

<!-- manuscript-example: {"mode":"test","stdout":"RUN example.ms::pipe flow\nPASS example.ms::pipe flow\n1 tests, 0 failed\n"} -->
```manuscript
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

Test output:

```text
RUN example.ms::pipe flow
PASS example.ms::pipe flow
1 tests, 0 failed
```

The parser trims surrounding whitespace, converts text to an optional integer,
and turns absence into an error with `ok_or()`. Only a successful reading reaches
`to_fahrenheit`. The test checks the familiar boiling point: 100 Celsius becomes
212 Fahrenheit.

`x | f` is `f(x)`; `x | .m()` is `x.m()`. Choose a pipe when it makes a sequence of
transformations easier to follow, and name an intermediate value when you need to
use it more than once. See [pipe flows](../core-language/basics/expressions.md#pipe-flows).

## Behavior on types

A record describes data. Methods describe operations on that data and live in an
`impl` block, outside the `type`. An interface names a set of operations that other
types can implement. Here, `Increment` requires a mutating operation, and `Counter`
provides it; `self` names the receiver inside that operation:

<!-- manuscript-example: {"mode":"test","stdout":"RUN example.ms::counter behavior\nPASS example.ms::counter behavior\n1 tests, 0 failed\n"} -->
```manuscript
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

Test output:

```text
RUN example.ms::counter behavior
PASS example.ms::counter behavior
1 tests, 0 failed
```

A type's own methods go in `impl Counter:`, without an interface:

<!-- manuscript-example: {"mode":"test","stdout":"RUN example.ms::own methods\nPASS example.ms::own methods\n1 tests, 0 failed\n"} -->
```manuscript
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

Test output:

```text
RUN example.ms::own methods
PASS example.ms::own methods
1 tests, 0 failed
```

`Self` names the receiver's type in these signatures, so a method that builds a new value writes `fn with_value(value: Int) Self` instead of repeating the type.

Use an interface when callers should depend on behavior rather than on the type. Free functions that mutate an argument are called as `reset(var counter)`. See [interfaces and implementations](../core-language/types/contracts.md#explicit-implementations).

## Reuse a function with generics

The collections used earlier are generic: `List[Int]` and `List[String]` use the
same collection operations while keeping different element types. Your own
functions can preserve that information too:

<!-- manuscript-example: {"mode":"run","stdout":"true\nfalse\n"} -->
```manuscript
fn same[T: Equal](left: T, right: T) Bool:
    return left == right

export fn main() Int:
    print(same(3, 3))
    print(same[String]("draft", "published"))
    return 0
```

```text
true
false
```

`T` stands for one concrete type at each call. The first call infers `Int`; the
second writes `String` explicitly. The `Equal` bound is the behavior the function
needs: it allows the body to compare its two inputs. Calling `same(3, "3")` is
rejected because one `T` cannot simultaneously mean `Int` and `String`.

Generics keep types visible to the compiler; they do not introduce an `any` value
or runtime reflection. The [generics chapter](../core-language/types/generics.md)
explains inference, bounds, generic records, defaults, and specialization.

## Files and cleanup

A file is a resource that must be closed. Put acquisition and use in the same
function so its scope expresses the resource's lifetime. Save this complete program
as `copy.ms`. Create `notes.txt` containing `Remember the milk` followed by a newline,
then run `ms run copy.ms` to copy at most one MiB into `backup.txt`:

<!-- manuscript-example: {"mode":"run","files":{"notes.txt":"Remember the milk\n"},"want_files":{"backup.txt":"Remember the milk\n"},"stdout":"Copied notes.txt to backup.txt\n"} -->
```manuscript
import open, write_file_bytes from "@std/os/fs.ms"

fn copy_notes() Unit!:
    let source = try open("notes.txt", flags: "r", mode: 0)
    let contents = try source.read_file(max_bytes: 1048576)
    try write_file_bytes(path: "backup.txt", data: contents, replace: true).wait()
    return ok(unit)

export fn main() Int:
    let outcome = copy_notes()
    if let _copied = outcome:
        print("Copied notes.txt to backup.txt")
        return 0
    print(outcome.err().message)
    return 1
```

```text
Copied notes.txt to backup.txt
```

`backup.txt` contains the same text as `notes.txt`. `try open` acquires the file or
returns an error before any read happens. The handle can use a `let` binding:
`read_file` is a non-mutating method in its Manuscript signature, even though reading
advances the underlying file position. `write_file_bytes` returns a promise;
`.wait()` takes the write result, which `try` checks before reporting success.

The file closes at the end of its scope, even on early return. `close()` returns a
`Result`: a function returning `T!` can report a failed close as its error; a
function without a compatible error result faults on one. Moving a resource
transfers cleanup responsibility, while borrowing it leaves responsibility with
its owner. Closing is separate from successfully delivering data: check fallible
writes and flushes rather than treating cleanup as proof of delivery. See
[cleanup](../core-language/cleanup/_index.md),
[resource captures](../core-language/functions/function-values-and-closures.md#resource-captures),
and the complete [file recipes](common-tasks.md).

## Start work and wait for its result

A promise represents work whose result you take once. Start your own work with
`promise(fn: ...)`, then call `wait()` where you need the result:

<!-- manuscript-example: {"mode":"run","stdout":"Total: 45\n"} -->
```manuscript
import promise from "@std/concurrency/promise.ms"

fn calculate() Int!:
    let pending = promise(fn: ok(12 + 8 + 25))
    let total = try pending.wait()
    return ok(total)

export fn main() Int:
    let outcome = calculate()
    if let total = outcome:
        print("Total: {total}")
        return 0
    print(outcome.err().message)
    return 1
```

```text
Total: 45
```

This small calculation illustrates the control flow, not a reason to add parallel
work to arithmetic. `promise` starts work eagerly; `wait` pauses until it finishes
and returns a result. Do not wait a second time for the same payload. Real uses
include overlapping independent file or network operations.

A promise can read captured values, but cannot mutate borrowed captures. Keep
mutable state with one owner and send updates through a pipe when needed. A fault
inside a promise becomes an error at `wait`, so handling the result is necessary
even when the callback always returns `ok(...)`. Timeouts are promise options;
dropping unfinished work requests cancellation and waits for it to end. The
[promises chapter](../core-language/concurrency/promises.md) explains start timing,
captures, timeouts, and cooperative cancellation before you depend on them.

## A few compiler errors to recognize

Save this complete but deliberately invalid program as `invalid.ms`. Each mistake
illustrates a rule introduced above:

<!-- manuscript-example: {"mode":"reject","stderr_contains":["cannot assign immutable binding count","expected Int, found String (in entry 2 of the literal, whose entries share one type)","missing argument quantity: Int in call to line_total"]} -->
```manuscript
fn line_total(price: Int, quantity: Int) Int:
    return price * quantity

export fn main() Int:
    let count = 2
    count = 3
    let mixed = [1, "two"]
    print(mixed)
    line_total(12)
    return count
```

Check it without running:

```sh
ms check invalid.ms
```

The command exits with status 1 and reports three errors. The diagnostic causes
are shown here without file positions, source excerpts, or suggested fixes:

```text
cannot assign immutable binding count
expected Int, found String (in entry 2 of the literal, whose entries share one type)
missing argument quantity: Int in call to line_total
```

Use `var` when `count` must change, keep the list's element types consistent, and
supply the required `quantity` argument.

Read the cause and suggested fix, correct one issue, and check again. The
[diagnostics guide](../developer-tooling/source/diagnostics.md) explains structured
output and mechanical fixes.

Next, [test your code](testing.md) and build a useful tool from the
[task recipes](common-tasks.md). Work through the
[language guide](../core-language/_index.md) for deeper explanations and exact
rules; keep the [API reference](../standard-library/reference/_index.md) nearby
when choosing library operations.
