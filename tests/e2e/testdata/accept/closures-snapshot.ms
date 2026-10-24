from "@std/testing.ms" import expect_equal, expect_true

test "closures read the variable they borrow":
    var offset = 3
    offset = 99

    let first = lambda:
        return offset
    let second = lambda:
        return True
    first() | try expect_equal(99)
    second() | try expect_true
