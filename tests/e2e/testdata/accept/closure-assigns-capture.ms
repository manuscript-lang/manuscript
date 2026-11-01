import expect_equal from "@std/test/test.ms"

test "a closure that only assigns a captured variable changes it":
    var xs = ["a", "b"]
    var n = 0

    let reset = fn:
        xs = ["c"]
        n = 7

    reset()
    xs | try expect_equal(["c"])
    n | try expect_equal(7)
