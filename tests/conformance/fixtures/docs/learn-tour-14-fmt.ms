# conform: tags=control-flow,formatter,interfaces,modules,parser,records,stdlib-testing,testing,tier-core,try-result
# conform: phase=parse
# conform: origin=documentation/learn/tour.md:265
from "@std/test.ms" import expect_equal

interface Increment:
    var def increment() -> Unit

type Counter:
    value: Int

impl Increment for Counter:
    var def increment() -> Unit:
        self.value = self.value + 1

def reset(var counter: Counter) -> Unit:
    counter.value = 0

test "counter behavior":
    var counter = Counter(0)
    counter.increment()
    try expect_equal(counter.value, 1)
    reset(var counter)
    try expect_equal(counter.value, 0)
