import {TextError} from "@std/core.ms"
import {expect_equal, expect_false, fail} from "@std/testing.ms"
import range from "@std/collections.ms"

fn checked(n: Int) Result[Int, TextError]:
    if n < 0:
        return error(TextError("negative"))

    return ok(n + 1)

fn chain(n: Int) Result[Int, TextError]:
    let v = try checked(n)

    return ok(v * 2)

fn deeper(n: Int) Result[Int, TextError]:
    let a = try chain(n)
    let b = try chain(a)

    return ok(a + b)

fn expression_try(n: Int) Result[Int, TextError]:
    let x = (try checked(n)) + 100

    return ok(x)

fn passthrough(n: Int) Result[Int, TextError]:
    return checked(n)

fn through_local(n: Int) Result[Int, TextError]:
    let r = checked(n)

    return r

fn halve(n: Int) Optional[Int]:
    if n % 2 != 0:
        return none

    return some(n / 2)

fn word(n: Int) Result[String, TextError]:
    if n == 0:
        return error(TextError("zero"))

    return ok("w{n}")

fn ratio(n: Int) Result[Float, TextError]:
    return ok(1.5)

fn nothing(flag: Bool) Result[Unit, TextError]:
    if flag:
        return ok(unit)

    return error(TextError("no"))

fn nested(n: Int) Optional[Optional[Int]]:
    if n == 0:
        return none

    return some(halve(n))

fn matched_value(n: Int) Int:
    return checked(n).get(-1)

fn closure_return(n: Int) Result[Int, TextError]:
    if let y = halve(n):
        return ok(y)

    return error(TextError("odd"))

fn sum_all(count: Int) Result[Int, TextError]:
    var total = 0

    for i in range(0, count):
        let v = try checked(i)

        total += v

    return ok(total)

test "result matching":
    let v = chain(3).get()

    try expect_equal(v, 8)

    let failure = chain(-1)

    try expect_false(not failure.is_error())
    try expect_equal(failure.err().message(), "negative")

test "try chains":
    let v = deeper(1).get()
    if not (v == 4 + 10): return fail("deeper {v}")

    let deeper_failure = deeper(-5)

    try expect_false(not deeper_failure.is_error())
    try expect_equal(deeper_failure.err().message(), "negative")

    let x = expression_try(4).get()

    try expect_equal(x, 105)
    try expect_false(not expression_try(-4).is_error())

    let total = sum_all(5).get()
    if not (total == 15): return fail("sum {total}")

test "boxed consumers":
    try expect_equal("{checked(2)}", "{passthrough(2)}")
    try expect_equal(checked(2), through_local(2))
    try expect_equal(checked(-2), passthrough(-2))

    let f = checked
    let v = f(6).get()

    try expect_equal(v, 7)
    try expect_equal(matched_value(3), 4)
    try expect_equal(matched_value(-3), -1)

test "optional and payload kinds":
    if let h = halve(8):
        try expect_equal(h, 4)
    else:
        return fail("halve none")

    try expect_false(halve(7).is_some())

    let w = word(3).get()

    try expect_equal(w, "w3")

    let r = ratio(1).get()

    try expect_equal(r, 1.5)
    nothing(true).get()

    if let inner = nested(4):
        try expect_equal(inner, some(2))
    else:
        return fail("nested none")

    let odd = closure_return(5)

    try expect_false(not odd.is_error())
    try expect_equal(odd.err().message(), "odd")

    let even = closure_return(6).get()

    try expect_equal(even, 3)

test "list at unwrap":
    let items = [10, 20, 30]

    try expect_equal(items.get(0), 10)
    try expect_equal(items.get(-1), 30)
    try expect_equal(items.get(1) + items.get(2), 50)
