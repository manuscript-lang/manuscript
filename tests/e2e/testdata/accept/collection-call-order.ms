from "@std/testing.ms" import expect_equal

test "receiver before index":
    let values = [7]
    var calls = 0
    let index: Optional[Int] = some(0)
    let result = values.get(
        match index:
            case some(i):
                calls += 1
                i
            case none: 0
    )
    try expect_equal(result, 7)
    try expect_equal(calls, 1)
