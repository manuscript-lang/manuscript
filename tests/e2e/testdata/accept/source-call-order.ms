import expect_equal from "@std/test.ms"

fn pair(a: Int, b: Int) Int: a * 10 + b

test "arguments":
    var value = 1
    let option: Int? = some(2)
    let result = pair(
        a: value,
        b: match option:
            some(i):
                value = 9
                i
            none: 0
    )
    try expect_equal(result, 12)

fn optional(value: Int?) Int: value.get()

fn defaulted(value: Int = 3) Int: value

fn identity[T](value: T) T: value

test "source call dispatch contracts":
    try expect_equal(optional(4), 4)
    try expect_equal(defaulted(5), 5)
    try expect_equal(defaulted(), 3)
    try expect_equal(pair(b: 2, a: 1), 12)

    let callback = pair
    try expect_equal(callback(a: 3, b: 4), 34)
    try expect_equal(identity(6), 6)
