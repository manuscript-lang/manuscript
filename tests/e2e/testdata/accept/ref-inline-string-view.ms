from "@std/testing.ms" import expect_equal
from "@std/collections.ms" import range

type Box:
    name: String
    other: String

impl Box:
    def short() -> ref String:
        return self.name.trim()

def churn(n: Int) -> Int:
    var total = 0
    for i in range(0, n):
        total += f"{i}".length()
    return total

def lend(line: String) -> ref String:
    return line.trim()

test "view of an inline string stays valid across calls":
    let line = "  abc  "
    let t = lend(line)
    let spent = churn(50)
    expect_equal(t, "abc")
    expect_equal(spent > 0, True)

test "view of an inline string field":
    let b = Box(name: " hi ", other: "x")
    let s = b.short()
    expect_equal(churn(20) > 0, True)
    expect_equal(s, "hi")
    expect_equal(b.other, "x")

def pressure(a: Int, b: Int, c: Int, d: Int) -> Int:
    var x = a * 3 + b
    var y = b * 5 + c
    var z = c * 7 + d
    var w = d * 11 + a

    for i in range(0, 40):
        x += y % 7 + i
        y += z % 11 + x % 3
        z += w % 13 + y % 5
        w += x % 17 + z % 7

    return x + y + z + w

def built(n: Int) -> String:
    return f"  {n}  "

test "view of a runtime-built inline string survives register pressure":
    let line = built(42)
    let t = lend(line)
    let spent = pressure(1, 2, 3, 4) + churn(30)
    expect_equal(spent > 0, True)
    expect_equal(t, "42")
    expect_equal(t.length(), 2)
    expect_equal(line.length(), 6)

test "view of an inline field built at runtime":
    let b = Box(name: built(7), other: "x")
    let s = b.short()
    expect_equal(pressure(4, 3, 2, 1) > 0, True)
    expect_equal(s, "7")
