import {expect_equal} from "@std/testing.ms"

test "receiver before index":
    var values = [7]
    let index: Optional[Int] = some(0)
    let result = values.at(
        match index:
            some(i):
                values = [9]
                i
            none: 0
    ).unwrap()
    result | try expect_equal(expected: 7)
