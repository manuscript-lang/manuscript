import exercise from "./outer.ms"
import Shared, share from "@std/concurrency/shared.ms"
import expect_equal from "@std/test/test.ms"

test "same display names keep nested resource cleanup":
    let log: Shared[List[Int]] = share([])
    exercise(log)
    log.get().clone() | try expect_equal([1])
