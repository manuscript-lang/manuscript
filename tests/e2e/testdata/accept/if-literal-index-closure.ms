from "@std/testing.ms" import expect_equal

type Box:
    n: Int

def describe(n: Int) -> String:
    return match n:
        case 0: "zero"
        case -1: "minus"
        case _: "other"

def pick(flag: Bool) -> Int:
    return (1 if flag else 2)

def maybe(n: Int) -> Optional[Int]:
    return n

def first_or(m: Optional[Int]) -> Int:
    if let v = m:
        return v

    return 0

test "if expression":
    expect_equal(pick(True), 1)
    expect_equal(pick(False), 2)

test "literal match":
    expect_equal(describe(0), "zero")
    expect_equal(describe(-1), "minus")
    expect_equal(describe(7), "other")

test "indexed assignment":
    var xs = [1, 2, 3]
    xs[1] = 9
    xs[2] += 1
    expect_equal(xs, [1, 9, 4])

test "optional wrap":
    let m: Optional[Int] = 5
    expect_equal(first_or(m), 5)
    expect_equal(first_or(maybe(3)), 3)

test "closure mutates capture":
    var total = 0
    var box = Box(n: 1)

    let add = lambda (x: Int) -> Unit:
        total += x
        box.n += x

    add(2)
    add(3)
    expect_equal(total, 5)
    expect_equal(box.n, 6)
