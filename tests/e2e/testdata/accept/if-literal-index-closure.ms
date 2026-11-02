import expect_equal from "@std/test/test.ms"

type Box:
    n: Int

fn describe(n: Int) String:
    return match n:
        0: "zero"
        -1: "minus"
        _: "other"

fn pick(flag: Bool) Int:
    return (if flag: 1 else: 2)

fn maybe(n: Int) Int?:
    return n

fn first_or(m: Int?) Int:
    if let v = m:
        return v

    return 0

test "if expression":
    try expect_equal(pick(true), 1)
    try expect_equal(pick(false), 2)

test "literal match":
    try expect_equal(describe(0), "zero")
    try expect_equal(describe(-1), "minus")
    try expect_equal(describe(7), "other")

test "indexed assignment":
    var xs = [1, 2, 3]
    xs[1] = 9
    xs[2] += 1
    try expect_equal(xs, [1, 9, 4])

test "optional wrap":
    let m: Int? = 5
    try expect_equal(first_or(m), 5)
    try expect_equal(first_or(maybe(3)), 3)

test "closure mutates capture":
    var total = 0
    var box = Box(n: 1)

    let add = fn(x: Int) Unit:
        total += x
        box.n += x

    add(2)
    add(3)
    try expect_equal(total, 5)
    try expect_equal(box.n, 6)
