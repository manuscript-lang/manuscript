import panic from "@std/core.ms"
import expect_contains, expect_equal, expect_fault from "@std/test/test.ms"

fn descend(n: Int) Int:
    if n == 0:
        return panic("tail recursion reached its base")
    return descend(n - 1)

fn bounded(n: Int) Int:
    if n == 0:
        return 0
    return bounded(n - 1)

fn runaway(n: Int) Int:
    return runaway(n)

test "final recursive calls keep their source frames":
    # Intentionally uncaught: the host regression checks the complete source trace.
    let _ = descend(6)

test "bounded final recursion returns below the stack limit":
    bounded(100000) | try expect_equal(0)

test "runaway final recursion respects the stack limit":
    let message = try expect_fault(
        fn:
            let _ = runaway(1)
    )
    message | try expect_contains("call depth limit exceeded")
