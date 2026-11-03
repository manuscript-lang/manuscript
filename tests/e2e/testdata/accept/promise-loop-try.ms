import expect_equal from "@std/test/test.ms"
import promise from "@std/concurrency/promise.ms"

test "try inside a loop over a list of promises":
    let a = promise(fn: ok(1))
    let b = promise(fn: ok(2))
    var total = 0

    for p in [a, b]:
        let value = try p.wait()
        total = total + value

    try expect_equal(total, 3)
