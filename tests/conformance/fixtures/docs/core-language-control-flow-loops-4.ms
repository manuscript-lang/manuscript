# conform: tags=control-flow,modules,mutation,stdlib-collections,stdlib-testing,testing,tier-stdlib,try-result
# conform: phase=test
# conform: origin=documentation/core-language/control-flow/loops.md:63
import range_by from "@std/collections.ms"
import expect_equal from "@std/test.ms"

test "sum even indexes":
    let indexes = try range_by(start: 0, end: 6, step: 2)
    var total = 0
    for index in indexes:
        total += index
    try expect_equal(total, 6)
