import first from "./first.ms"
import second from "./second.ms"
import expect_equal from "@std/test/test.ms"

test "map add generic and bound calls retain lexical key evidence":
    (try first()) | try expect_equal(2)
    (try second()) | try expect_equal(3)
