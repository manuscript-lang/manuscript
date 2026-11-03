# conform: tags=closures,control-flow,faults,formatter,lists,modules,mutation,parser,stdlib-errors,stdlib-testing,testing,tier-stdlib,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/accept/try-statement.ms
import expect_equal from "@std/test/test.ms"

fn parse(n: Int) Int!Error:
    if n < 0:
        return error(Error("neg"))

    return ok(n)

fn bound(n: Int) Int!Error:
    let v = try parse(n)
    return ok(v + 1)

fn reassigned(n: Int) Int!Error:
    var total = 1
    total = try parse(n)
    return ok(total * 2)

fn check(n: Int) Unit!Error:
    if n < 0:
        return error(Error("neg"))

    return ok(unit)

fn discarded(n: Int) Int!Error:
    try check(n)
    return ok(7)

fn code(r: Int!Error) Int:
    return r.get(-1)

fn nested(n: Int) Int!Error:
    return ok((try parse(n)) + (try parse(n - 5)))

fn chained(n: Int) Int!Error:
    let a = try bound(n)
    let b = try reassigned(a - 10)
    return ok(b)

fn in_loop(values: List[Int]) Int!Error:
    var sum = 0
    for v in values:
        sum += try parse(v)
    return ok(sum)

fn in_lambda(n: Int) Int!Error:
    let inner = fn() Int!Error:
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
