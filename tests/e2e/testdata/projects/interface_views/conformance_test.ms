import (
    invoke from "./domain.ms",
    left from "./left.ms",
    right from "./right.ms",
    expect_equal from "@std/test/test.ms",
)

test "each module keeps its own view implementation":
    let first = left()
    let second = right()
    let bound = first.read
    bound() | try expect_equal(11)
    second.read() | try expect_equal(22)
    invoke(first) | try expect_equal(11)
    invoke(second) | try expect_equal(22)
