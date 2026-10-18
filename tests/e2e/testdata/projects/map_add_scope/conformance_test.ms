import first from "./first.ms"
import second from "./second.ms"
import expect_equal from "@std/testing.ms"

test "map add generic and bound calls retain lexical key evidence":
    (try first()) | try expect_equal(expected: 2)
    (try second()) | try expect_equal(expected: 3)
