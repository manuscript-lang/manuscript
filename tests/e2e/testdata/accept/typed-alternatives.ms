import {expect_equal, fail} from "@std/testing.ms"
import range from "@std/collections.ms"

fn checked(n: Int) -> Result[Int, String]:
    if n < 0:
        return error(cause: "negative")

    return ok(value: n + 1)

fn chain(n: Int) -> Result[Int, String]:
    let v = try checked(n)
    return ok(value: v * 2)

fn deeper(n: Int) -> Result[Int, String]:
    let a = try chain(n)
    let b = try chain(a)
    return ok(value: a + b)

fn expression_try(n: Int) -> Result[Int, String]:
    let x = (try checked(n)) + 100
    return ok(value: x)

fn passthrough(n: Int) -> Result[Int, String]:
    return checked(n)

fn through_local(n: Int) -> Result[Int, String]:
    let r = checked(n)
    return r

fn halve(n: Int) -> Optional[Int]:
    if n % 2 != 0:
        return none

    return some(value: n / 2)

fn word(n: Int) -> Result[String, String]:
    if n == 0:
        return error(cause: "zero")

    return ok(value: "w{n}")

fn ratio(n: Int) -> Result[Float, String]:
    return ok(value: 1.5)

fn nothing(flag: Bool) -> Result[Unit, String]:
    if flag:
        return ok(value: unit)

    return error(cause: "no")

fn nested(n: Int) -> Optional[Optional[Int]]:
    if n == 0:
        return none

    return some(value: halve(n))

fn matched_value(n: Int) -> Int:
    let r = match checked(n):
        ok(v):
            v
        error(_):
            -1

    return r

fn closure_return(n: Int) -> Result[Int, String]:
    let y = match halve(n):
        some(h):
            h
        none:
            return error(cause: "odd")

    return ok(value: y)

fn sum_all(count: Int) -> Result[Int, String]:
    var total = 0

    for i in range(0, count):
        let v = try checked(i)
        total = total + v

    return ok(value: total)

test "result matching":
    match chain(3):
        ok(v):
            try expect_equal(v, 8)
        error(_):
            return fail(message: "chain error")

    match chain(-1):
        ok(_):
            return fail(message: "chain should fail")
        error(cause):
            try expect_equal(cause, "negative")

test "try chains":
    match deeper(1):
        ok(v):
            if not (v == 4 + 10): return fail(message: "deeper {v}")
        error(_):
            return fail(message: "deeper error")

    match deeper(-5):
        ok(_):
            return fail(message: "deeper should fail")
        error(e):
            try expect_equal(e, "negative")

    match expression_try(4):
        ok(v):
            try expect_equal(v, 105)
        error(_):
            return fail(message: "expression try error")

    match expression_try(-4):
        ok(_):
            return fail(message: "expression try should fail")
        error(_):
            unit

    match sum_all(5):
        ok(v):
            if not (v == 15): return fail(message: "sum {v}")
        error(_):
            return fail(message: "sum error")

test "boxed consumers":
    "{checked(2)}" | try expect_equal(expected: "{passthrough(2)}")
    checked(2) | try expect_equal(expected: through_local(2))
    checked(-2) | try expect_equal(expected: passthrough(-2))
    let f = checked

    match f(n: 6):
        ok(v):
            try expect_equal(v, 7)
        error(_):
            return fail(message: "first class error")

    matched_value(3) | try expect_equal(expected: 4)
    matched_value(-3) | try expect_equal(expected: -1)

test "optional and payload kinds":
    match halve(8):
        some(h):
            try expect_equal(h, 4)
        none:
            return fail(message: "halve none")

    match halve(7):
        some(_):
            return fail(message: "halve odd")
        none:
            unit

    match word(3):
        ok(w):
            try expect_equal(w, "w3")
        error(_):
            return fail(message: "word error")

    match ratio(1):
        ok(r):
            try expect_equal(r, 1.5)
        error(_):
            return fail(message: "ratio error")

    match nothing(true):
        ok(u):
            try expect_equal(u, unit)
        error(_):
            return fail(message: "unit error")

    match nested(4):
        some(inner):
            try expect_equal(inner, some(value: 2))
        none:
            return fail(message: "nested none")

    match closure_return(5):
        ok(_):
            return fail(message: "closure return should fail")
        error(e):
            try expect_equal(e, "odd")

    match closure_return(6):
        ok(v):
            try expect_equal(v, 3)
        error(_):
            return fail(message: "closure return error")

test "list at unwrap":
    let items = [10, 20, 30]
    items.at(0).unwrap() | try expect_equal(expected: 10)
    items.at(-1).unwrap() | try expect_equal(expected: 30)
    (items.at(1).unwrap() + items.at(2).unwrap()) | try expect_equal(expected: 50)
