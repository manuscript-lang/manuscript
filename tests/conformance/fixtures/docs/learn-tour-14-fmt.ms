# conform: tags=control-flow,formatter,interfaces,modules,parser,records,stdlib-testing,testing,tier-core,try-result
# conform: phase=parse
# conform: origin=documentation/learn/tour.md:265
import expect_equal from "@std/testing.ms"

interface Increment:
    fn increment() Unit

type Counter:
    value: Int

impl Increment for Counter:
    fn increment() Unit:
        self.value = self.value + 1

fn reset(counter: Counter) Unit:
    counter.value = 0

test "counter behavior":
    let counter = Counter(0)
    counter.increment()
    try expect_equal(counter.value, 1)
    reset(counter)
    try expect_equal(counter.value, 0)
