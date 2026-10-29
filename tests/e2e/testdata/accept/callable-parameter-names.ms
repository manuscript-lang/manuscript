import expect_equal from "@std/test.ms"

fn first(amount: Int) Int: amount + 1

fn second(value: Int) Int: value + 2

fn choose[T](left: T, right: T) T: left

type Pair[T]:
    left: T
    right: T

test "callable identity uses ordered types rather than parameter names":
    let selected = choose(first, second)
    try expect_equal(selected(3), 4)
    try expect_equal(choose(second, first)(3), 5)

    let callbacks = [first, second]
    try expect_equal(callbacks[0](3), 4)
    try expect_equal(callbacks[1](3), 5)

    let pair = Pair(first, second)
    try expect_equal(pair.left(3), 4)
    try expect_equal(pair.right(3), 5)

    var callback = first
    callback = second
    try expect_equal(callback(3), 5)

    let factory = fn(flag: Bool):
        if flag:
            return first

        return second

    try expect_equal(factory(true)(3), 4)
    try expect_equal(factory(false)(3), 5)
