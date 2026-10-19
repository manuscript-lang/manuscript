# conform: tags=control-flow,formatter,modules,mutation,parser,stdlib-collections,stdlib-testing,testing,tier-stdlib,try-result
# conform: phase=parse
# conform: origin=documentation/learn/tour.md:91
import range from "@std/collections.ms"
import expect_equal from "@std/testing.ms"

test "count five iterations":
    var total = 0
    for index in range(0, 5):
        total += index
    try expect_equal(total, 10)
