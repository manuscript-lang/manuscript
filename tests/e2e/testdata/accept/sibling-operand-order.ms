import Decimal from "@std/decimal.ms"
import panic from "@std/faults.ms"

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
    if items != [1, 5, 50]: return panic("list element read after a later match")

    let texts = [
        y,
        match some("b"):
        some(value):
            y = "z"
            value
        none: ""
    ]
    if texts != ["a", "b"]: return panic("text element read after a later match")

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
    if entries.length() != 2: return panic("map key read after a later match")
    if entries.get(key: 1) != some(5): return panic(
        "first map key changed by a later match"
    )

test "generic binary operands read before a later match assigns them":
    var amount = 1.5d
    let sum = amount + match some(2.5d):
    some(value):
        amount = 100d
        value
    none: 0d
    if sum != 4d: return panic("decimal operand read after a later match")

type Cell:
    n: Int
    s: String

test "field assignment evaluates its receiver before the value":
    var cell = Cell(n: 1, s: "a")
    let original = cell

    cell.n = match some(2):
    some(value):
        cell = Cell(n: 100, s: "replacement")
        value
    none: 0

    if original.n != 2: return panic(
        "numeric field write used the receiver chosen by the value"
    )
    if cell.n != 100: return panic("replacement receiver was modified")

    var texts = Cell(n: 1, s: "a")
    let before = texts

    texts.s = match some("q"):
    some(value):
        texts = Cell(n: 100, s: "replacement")
        value
    none: ""

    if before.s != "q": return panic(
        "text field write used the receiver chosen by the value"
    )
