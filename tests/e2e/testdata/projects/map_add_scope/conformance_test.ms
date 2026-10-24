from "./first.ms" import first
from "./second.ms" import second
from "@std/testing.ms" import expect_equal

test "map add generic and bound calls retain lexical key evidence":
    (try first()) | try expect_equal(2)
    (try second()) | try expect_equal(3)
