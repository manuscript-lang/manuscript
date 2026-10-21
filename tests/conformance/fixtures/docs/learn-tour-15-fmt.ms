# conform: tags=formatter,interfaces,modules,parser,records,stdlib-testing,testing,tier-core,try-result
# conform: phase=parse
# conform: origin=documentation/learn/tour.md:292
import expect_equal from "@std/testing.ms"

type Counter:
    value: Int

impl Counter:
    var fn increment() Unit:
        self.value = self.value + 1

test "own methods":
    var counter = Counter(0)
    counter.increment()
    try expect_equal(counter.value, 1)
