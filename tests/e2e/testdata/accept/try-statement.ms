from "@std/core.ms" import TextError
from "@std/test.ms" import expect_equal

def parse(n: Int) -> Result[Int, TextError]:
    if n < 0:
        return error(TextError("neg"))

    return ok(n)

def bound(n: Int) -> Result[Int, TextError]:
    let v = try parse(n)
    return ok(v + 1)

def reassigned(n: Int) -> Result[Int, TextError]:
    var total = 1
    total = try parse(n)
    return ok(total * 2)

def check(n: Int) -> Result[Unit, TextError]:
    if n < 0:
        return error(TextError("neg"))

    return ok(())

def discarded(n: Int) -> Result[Int, TextError]:
    try check(n)
    return ok(7)

def code(r: Result[Int, TextError]) -> Int:
    return r.get(-1)

def nested(n: Int) -> Result[Int, TextError]:
    return ok((try parse(n)) + (try parse(n - 5)))

def chained(n: Int) -> Result[Int, TextError]:
    let a = try bound(n)
    let b = try reassigned(a - 10)
    return ok(b)

def in_loop(values: List[Int]) -> Result[Int, TextError]:
    var sum = 0
    for v in values:
        sum += try parse(v)
    return ok(sum)

def in_lambda(n: Int) -> Result[Int, TextError]:
    let inner = lambda () -> Result[Int, TextError]:
        let v = try parse(n)
        return ok(v * 10)

    let r = try inner()
    return ok(r + 1)

test "statement try returns the error and binds the value":
    try expect_equal(code(bound(4)), 5)
    try expect_equal(code(bound(-1)), -1)
    try expect_equal(code(reassigned(3)), 6)
    try expect_equal(code(reassigned(-2)), -1)
    try expect_equal(code(discarded(1)), 7)
    try expect_equal(code(discarded(-1)), -1)

test "try nested in expressions and chains still propagates":
    try expect_equal(code(nested(6)), 7)
    try expect_equal(code(nested(2)), -1)
    try expect_equal(code(chained(12)), 6)
    try expect_equal(code(chained(3)), -1)

test "try in loops and lambdas":
    try expect_equal(code(in_loop([1, 2, 3])), 6)
    try expect_equal(code(in_loop([1, -2, 3])), -1)
    try expect_equal(code(in_lambda(2)), 21)
    try expect_equal(code(in_lambda(-2)), -1)
