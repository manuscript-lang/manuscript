# conform: tags=closures,control-flow,faults,interpolation,lists,match,modules,mutation,optional,stdlib-errors,stdlib-testing,strings,testing,tier-stdlib,try-result
# conform: phase=test
# conform: origin=tests/e2e/testdata/accept/local-closures-keep-semantics.ms
import {TextError} from "@std/errors.ms"
import {expect_true} from "@std/testing.ms"

fn bump(factor: Int) Int:
    var offset = 10
    let scale = fn(value: Int) Int: value * factor + offset
    offset = 99
    return scale(value: 2)

fn lookup(limit: Int) Int:
    let find = fn(key: Int) Optional[Int]:
        if key < limit:
            return some(key * 2)

        return none
    var total = 0
    var i = 0

    while i < 5:
        match find(key: i):
            some(found):
                total = total + found
            none:
                total = total + 100

        i = i + 1

    return total

fn parse(text: String) Result[Int, TextError]:
    let guard = fn(number: Int) Result[Int, TextError]:
        if number < 0:
            return Result[Int, TextError].error(TextError("negative"))

        return Result[Int, TextError].ok(number)
    let checked = try guard(number: text.length())
    return Result[Int, TextError].ok(checked + 1)

fn labels(prefix: String) String:
    let join = fn(left: String, right: String) String: "{prefix}{left}-{right}"
    return join(left: "a", right: "b")

fn reordered() Int:
    let subtract = fn(left: Int, right: Int) Int: left - right
    return subtract(right: 2, left: 7)

fn passed() List[Int]:
    let double = fn(value: Int) Int: value * 2
    return [1, 2, 3].map(double)

fn nested(n: Int) Int:
    let inner = fn(x: Int) Int: x + 1
    let outer = fn(y: Int) Int: inner(x: y) * 2
    return outer(y: n)

test "local closures":
    try expect_true((bump(factor: 3) == 16))
    try expect_true((lookup(limit: 3) == 0 + 2 + 4 + 100 + 100))
    try expect_true((parse(text: "abc") == Result[Int, TextError].ok(4)))
    try expect_true((labels(prefix: ">") == ">a-b"))
    try expect_true((reordered() == 5))
    try expect_true((passed().length() == 3 and passed().get(index: 2) == 6))
    try expect_true((nested(n: 4) == 10))
