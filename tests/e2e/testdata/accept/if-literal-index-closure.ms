import {expect_equal} from "@std/testing.ms"

type Box:
    n: Int

fn describe(n: Int) String:
    return match n:
        0: "zero"
        -1: "minus"
        _: "other"

fn pick(flag: Bool) Int:
    return if flag: 1 else: 2

fn maybe(n: Int) Optional[Int]:
    return n

fn first_or(m: Optional[Int]) Int:
    if let v = m:
        return v

    return 0

test "if expression":
    expect_equal(pick(true), 1)
    expect_equal(pick(false), 2)

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
    let add = fn(x: Int) Unit:
        total += x
        box.n += x
    add(2)
    add(3)
    expect_equal(total, 5)
    expect_equal(box.n, 6)
