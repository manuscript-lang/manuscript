import {expect_equal} from "@std/testing.ms"

export fn main() -> Int:
    var number = 1
    let total = number + (
        match some(1):
            some(value):
                number = number + 1
                value
            none: 0
    )
    if total != 2:
        return 1

    return 0

test "left operand is evaluated before a match operand mutates it":
    main() | try expect_equal(expected: 0)
