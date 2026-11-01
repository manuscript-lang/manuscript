# conform: tags=control-flow,formatter,modules,mutation,parser,stdlib-collections,stdlib-testing,testing,tier-stdlib,try-result
# conform: phase=parse
# conform: origin=documentation/learn/tour.md:91
import expect_equal from "@std/test/test.ms"

test "count five iterations":
    var total = 0
    for index in 0..5:
        total += index
    try expect_equal(total, 10)
