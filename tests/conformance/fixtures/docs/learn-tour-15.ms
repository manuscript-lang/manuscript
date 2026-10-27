# conform: tags=interfaces,modules,records,stdlib-testing,testing,tier-core,try-result
# conform: phase=test
# conform: origin=documentation/learn/tour.md:292
from "@std/test.ms" import expect_equal

type Counter:
    value: Int

impl Counter:
    var def increment() -> Unit:
        self.value = self.value + 1

test "own methods":
    var counter = Counter(0)
    counter.increment()
    try expect_equal(counter.value, 1)
