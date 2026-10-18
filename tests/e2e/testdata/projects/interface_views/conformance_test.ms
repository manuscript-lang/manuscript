import invoke from "./domain.ms"
import left from "./left.ms"
import right from "./right.ms"
import expect_equal from "@std/testing.ms"

test "each module keeps its own view implementation":
    let first = left()
    let second = right()
    let bound = first.read
    bound() | try expect_equal(expected: 11)
    second.read() | try expect_equal(expected: 22)
    invoke(first) | try expect_equal(expected: 11)
    invoke(second) | try expect_equal(expected: 22)
