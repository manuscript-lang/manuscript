# conform: tags=control-flow,formatter,modules,mutation,parser,stdlib-collections,stdlib-testing,testing,tier-stdlib,try-result
# conform: phase=parse
# conform: origin=documentation/learn/tour.md:91
from "@std/collections.ms" import range
from "@std/test.ms" import expect_equal

test "count five iterations":
    var total = 0
    for index in range(0, 5):
        total += index
    try expect_equal(total, 10)
