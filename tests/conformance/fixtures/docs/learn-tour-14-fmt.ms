# conform: tags=control-flow,formatter,interfaces,modules,parser,records,stdlib-testing,testing,tier-core,try-result
# conform: phase=parse
# conform: origin=documentation/learn/tour.md:265
import expect_equal from "@std/test.ms"

interface Increment:
    var fn increment() Unit

type Counter:
    value: Int

impl Increment for Counter:
    var fn increment() Unit:
        self.value = self.value + 1

fn reset(var counter: Counter) Unit:
    counter.value = 0

test "counter behavior":
    var counter = Counter(0)
    counter.increment()
    try expect_equal(counter.value, 1)
    reset(var counter)
    try expect_equal(counter.value, 0)
