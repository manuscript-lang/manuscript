# conform: tags=decimal,faults,formatter,match,modules,mutation,optional,parser,records,stdlib-decimal,stdlib-testing,strings,testing,tier-stdlib,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/accept/sibling-operand-order.ms
import expect_equal from "@std/test.ms"
import Decimal from "@std/decimal.ms"

test "list elements read before a later match assigns them":
    var x = 1
    var y = "a"
    let items = [
        x,
        match some(5):
            some(value):
                x = 50
                value
            none: 0
        ,
        x
    ]
    try expect_equal(items, [1, 5, 50])

    let texts = [
        y,
        match some("b"):
            some(value):
                y = "z"
                value
            none: ""
    ]
    try expect_equal(texts, ["a", "b"])

test "map keys read before a later match assigns them":
    var key = 1
    let entries = {
        key: match some(5):
            some(value):
                key = 50
                value
            none: 0
        ,
        key: key
    }
    try expect_equal(entries.length(), 2)
    try expect_equal(entries.get(key: 1), some(5))

test "generic binary operands read before a later match assigns them":
    var amount = 1.5d
    let sum = amount + match some(2.5d):
        some(value):
            amount = 100d
            value
        none: 0d
    try expect_equal(sum, 4d)

type Cell:
    n: Int
    s: String

test "field assignment keeps sibling field writes made while evaluating the value":
    var cell = Cell(n: 1, s: "a")

    cell.n = match some(2):
        some(value):
            cell.s = "changed"
            value
        none: 0

    try expect_equal(cell.n, 2)
    try expect_equal(cell.s, "changed")
