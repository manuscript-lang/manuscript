from "@std/testing.ms" import expect_equal

def first(amount: Int) -> Int: amount + 1

def second(value: Int) -> Int: value + 2

def choose[T](left: T, right: T) -> T: left

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

    let factory = lambda (flag: Bool):
        if flag:
            return first

        return second

    try expect_equal(factory(True)(3), 4)
    try expect_equal(factory(False)(3), 5)
