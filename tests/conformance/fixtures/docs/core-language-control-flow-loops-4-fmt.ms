# conform: tags=control-flow,formatter,modules,mutation,parser,stdlib-collections,stdlib-testing,testing,tier-stdlib,try-result
# conform: phase=parse
# conform: origin=documentation/core-language/control-flow/loops.md:63
from "@std/collections.ms" import range_by
from "@std/test.ms" import expect_equal

test "sum even indexes":
    let indexes = try range_by(start: 0, end: 6, step: 2)
    var total = 0
    for index in indexes:
        total += index
    try expect_equal(total, 6)
