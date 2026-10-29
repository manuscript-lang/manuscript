import expect_equal from "@std/test.ms"

export fn main() Int:
    var number = 1
    let total = (
        number
        + (
            match some(1):
                some(value):
                    number += 1
                    value
                none: 0
        )
    )
    if total != 2:
        return 1

    return 0

test "operands retain evaluation order":
    main() | try expect_equal(0)
