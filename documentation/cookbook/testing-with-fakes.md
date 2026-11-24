+++
title = "Tests with fakes"
weight = 21
+++

# Tests with fakes

Test code that sends email, calls a service or reads the clock without touching the real thing. The code takes an interface, production passes the real implementation, and the test passes a fake that records what happened or fails on demand.

## Replace a dependency with a fake

Save as `notify_test.ms` and run `ms test notify_test.ms`. `notify_all` depends only on `Mailer`. The test's `FakeMailer` fails for the addresses it is given, so both the normal path and the error path run with no network.

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
import expect_equal from "@std/test/test.ms"

interface Mailer {
    fn send(to, subject String) Void!
}

fn notify_all(mailer Mailer, users List[String]) List[String] {
    var failed List[String] = []
    for user in users {
        if mailer.send(user, "Welcome").is_error() {
            failed.append(user.clone())
        }
    }
    return failed
}

type FakeMailer {
    broken Set[String] = Set[String]()
}

fn FakeMailer.send(to, subject String) Void! {
    if self.broken.contains(to) {
        return error(Error("mailbox full", kind: "EDQUOT"))
    }
    return ok()
}

test "every user gets a message" {
    failed := notify_all(FakeMailer(), ["ada", "sam"])
    expect_equal(failed, [])?
}

test "a failing mailbox is reported" {
    mailer := FakeMailer(broken: ["sam"].to_set())
    failed := notify_all(mailer, ["ada", "sam", "lin"])
    expect_equal(failed, ["sam"])?
}
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

## Control time

Save as `clock_test.ms`. Pass the current time in instead of reading it inside the function, and the test can choose any moment.

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
import expect_equal from "@std/test/test.ms"

fn is_expired(issued_at, now, lifetime Int) Bool {
    return now - issued_at >= lifetime
}

test "a token expires at the end of its lifetime" {
    expect_equal(is_expired(100, 159, 60), false)?
    expect_equal(is_expired(100, 160, 60), true)?
}
```

```text
RUN clock_test.ms::a token expires at the end of its lifetime
PASS clock_test.ms::a token expires at the end of its lifetime
1 tests, 0 failed
```

Production code calls `now()` from `@std/time.ms` once, at the edge, and passes the result down.
