+++
title = "Tests with fakes"
weight = 11
+++

# Tests with fakes

Test code that sends email, calls a service or reads the clock without touching the real thing. The code takes an interface, production passes the real implementation, and the test passes a fake that records what happened or fails on demand.

## Replace a dependency with a fake

Save as `notify_test.ms` and run `ms test notify_test.ms`. `notify_all` depends only on `Mailer`. The test's `FakeMailer` fails for the addresses it is given, so both the normal path and the error path run with no network.

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
import expect_equal from "@std/test/test.ms"

interface Mailer:
    fn send(to: String, subject: String) Void!

fn notify_all(mailer: Mailer, users: List[String]) List[String]:
    var failed: List[String] = []
    for user in users:
        if mailer.send(user, "Welcome").is_error():
            failed.append(user.clone())
    return failed

type FakeMailer:
    broken: Set[String] = Set[String]()

fn FakeMailer.send(to: String, subject: String) Void!:
    if self.broken.contains(to):
        return error(Error("mailbox full", kind: "EDQUOT"))
    return ok()

test "every user gets a message":
    failed := notify_all(FakeMailer(), ["ada", "sam"])
    expect_equal(failed, [])?

test "a failing mailbox is reported":
    mailer := FakeMailer(broken: ["sam"].to_set())
    failed := notify_all(mailer, ["ada", "sam", "lin"])
    expect_equal(failed, ["sam"])?
```

```text
RUN notify_test.ms::every user gets a message
PASS notify_test.ms::every user gets a message
RUN notify_test.ms::a failing mailbox is reported
PASS notify_test.ms::a failing mailbox is reported
2 tests, 0 failed
```

- A type satisfies an interface by having the methods; nothing is declared. The real mailer in production is any other type with a `send` of the same shape.
- A fake can fail on demand or return fixed data. To check what the code did, assert on what it returns, as above.
- Fakes stay in the test file. Keep the interface as small as the code under test needs; one or two operations are easier to fake than a whole client.

## Record calls with a mock

`@std/test/mock.ms` has `Mock0` to `Mock3` (the number is how many arguments the call takes). A mock answers with a preset value, records every call, and checks them afterwards. Pass it where the code expects a function, wrapped in a closure.

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
import Mock1 from "@std/test/mock.ms"
import expect_equal from "@std/test/test.ms"

fn charge_all(charge: fn(String) Int, users: List[String]) Int:
    var total = 0
    for user in users:
        total += charge(user)
    return total

test "each user is charged, the first at a special price":
    var charge = Mock1[String, Int](fallback: 5)
    charge.returns_once(2)
    total := charge_all(fn user: charge.call(user), ["ada", "sam"])
    expect_equal(total, 7)?
    charge.expect_called_times(2)?
    charge.expect_called_with("sam")?
    charge.expect_last_called_with("sam")?
```

```text
RUN mock_test.ms::each user is charged, the first at a special price
PASS mock_test.ms::each user is charged, the first at a special price
1 tests, 0 failed
```

- An answer comes from the first matching `returns_for(args, value)` rule, else the next `returns_once(value)`, else `fallback`. `R` can be a Result or optional, so a mock can fail on demand: `Mock1[String, Int!]`.
- `calls` lists the arguments of every call (`Call2` and `Call3` records for two and three arguments). Arguments are cloned in, so the caller keeps its values.
- `expect_called_times`, `expect_not_called`, `expect_called_with`, `expect_last_called_with`, `expect_called_matching(check)` (for arguments only partly known) and `expect_answers_used` (every `returns_once` was consumed) fail the test with the recorded calls in the message. `reset()` clears calls and queued answers.
- A mock replaces what code is given. Code that reaches the clock or files directly has to take that as a parameter first.

## Replace a function for one block

`fake(original, replacement, body)` in `@std/test/test.ms` runs `body` with `replacement` standing in for `original`. Every call to `original`, from `body` and from promises it starts, runs `replacement`; when `body` returns, the original is back. Use it for the program's boundaries: code that reaches the clock, the environment, a file or the network, or a function you mark as a boundary with `// ms: effect NAME`. Anything else is a function you can pass in as a parameter, and faking it would tie the test to how the code is built.

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
import Mock1 from "@std/test/mock.ms"
import expect_equal, fake from "@std/test/test.ms"

// ms: effect shop.read
fn price(item: String) Int:
    return 100

fn total(items: List[String]) Int:
    var sum = 0
    for item in items:
        sum += price(item)
    return sum

test "the price lookup is replaced for the block":
    var lookup = Mock1[String, Int](fallback: 5)
    fake(price, fn item: lookup.call(item), fn:
        expect_equal(total(["ada", "sam"]), 10)?
        return ok()
    )?
    lookup.expect_called_with("sam")?
    expect_equal(total(["ada"]), 100)?
```

```text
RUN fake_test.ms::the price lookup is replaced for the block
PASS fake_test.ms::the price lookup is replaced for the block
1 tests, 0 failed
```

- Name the function as a plain reference. The replacement has the same function type, so the checker proves it fits, and it may capture and change the test's variables, as `lookup` does here.
- Only a function that declares an effect can be faked: a standard-library boundary (`now`, `read_file`) or your own, marked `// ms: effect shop.read` directly above it. Faking any other function is an error that says so. A method that declares an effect is named through an object, `fake(shop.price, fn item: ...)`, and is replaced for every object of its type; the replacement takes the other arguments, not the object. Not a generic function, or one that changes an argument or its object or returns a borrow.
- Fakes nest; the innermost wins. Only `ms test` builds route calls through the table, so `ms run` and `ms build` call the function directly.
- Everything else: pass the value in, as in the sections above.

## Control time

Save as `clock_test.ms`. Pass the current time in instead of reading it inside the function, and the test can choose any moment.

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
import expect_equal from "@std/test/test.ms"

fn is_expired(issued_at: Int, now: Int, lifetime: Int) Bool:
    return now - issued_at >= lifetime

test "a token expires at the end of its lifetime":
    expect_equal(is_expired(100, 159, 60), false)?
    expect_equal(is_expired(100, 160, 60), true)?
```

```text
RUN clock_test.ms::a token expires at the end of its lifetime
PASS clock_test.ms::a token expires at the end of its lifetime
1 tests, 0 failed
```

Production code calls `now()` from `@std/time.ms` once, at the edge, and passes the result down.
