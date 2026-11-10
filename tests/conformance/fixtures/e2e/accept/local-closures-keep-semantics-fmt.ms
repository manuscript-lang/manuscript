// conform: tags=closures,control-flow,faults,formatter,interpolation,lists,match,modules,mutation,optional,parser,stdlib-errors,stdlib-testing,strings,testing,tier-stdlib,try-result
// conform: phase=parse
// conform: origin=tests/e2e/testdata/accept/local-closures-keep-semantics.ms
import expect_true from "@std/test/test.ms"

fn bump(factor: Int) Int:
    var offset = 10
    offset = 99

    scale := fn(value: Int) Int: value * factor + offset
    return scale(value: 2)

fn lookup(limit: Int) Int:
    find := fn(key: Int) Int?:
        if key < limit:
            return (key * 2)

        return none

    var total = 0
    var i = 0

    while i < 5:
        match find(key: i):
            found:
                total = total + found
            none:
                total = total + 100

        i = i + 1

    return total

fn parse(text: String) Int!Error:
    guard := fn(number: Int) Int!Error:
        if number < 0:
            return Result[Int, Error].error(Error("negative"))

        return Result[Int, Error].ok(number)

    checked := try guard(number: text.length())
    return Result[Int, Error].ok(checked + 1)

fn labels(prefix: String) String:
    join := fn(left: String, right: String) String: "{prefix}{left}-{right}"
    return join(left: "a", right: "b")

fn reordered() Int:
    subtract := fn(left: Int, right: Int) Int: left - right
    return subtract(right: 2, left: 7)

fn passed() List[Int]:
    double := fn(value: Int) Int: value * 2
    return [1, 2, 3].map(double)

fn nested(n: Int) Int:
    inner := fn(x: Int) Int: x + 1
    outer := fn(y: Int) Int: inner(x: y) * 2
    return outer(y: n)

test "local closures":
    try expect_true((bump(factor: 3) == 105))
    try expect_true((lookup(limit: 3) == 0 + 2 + 4 + 100 + 100))
    try expect_true((parse(text: "abc") == Result[Int, Error].ok(4)))
    try expect_true((labels(prefix: ">") == ">a-b"))
    try expect_true((reordered() == 5))
    try expect_true((passed().length() == 3 and passed().get(index: 2) == 6))
    try expect_true((nested(n: 4) == 10))
