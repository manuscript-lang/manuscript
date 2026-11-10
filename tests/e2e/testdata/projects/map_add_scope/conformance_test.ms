import (
    first from "./first.ms",
    second from "./second.ms",
    expect_equal from "@std/test/test.ms",
)

test "map add generic and bound calls retain lexical key evidence":
    (try first()) | try expect_equal(2)
    (try second()) | try expect_equal(3)
