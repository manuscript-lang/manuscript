# conform: tags=formatter,modules,parser,stdlib-testing,testing,tier-core,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/projects/map_add_scope/conformance_test.ms
from "./first.ms" import first
from "./second.ms" import second
from "@std/testing.ms" import expect_equal

test "map add generic and bound calls retain lexical key evidence":
    (try first()) | try expect_equal(2)
    (try second()) | try expect_equal(3)
