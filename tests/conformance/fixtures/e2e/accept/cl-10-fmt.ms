# conform: tags=control-flow,formatter,interfaces,modules,parser,records,stdlib-testing,testing,tier-core,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/accept/cl-10.ms
import expect_equal from "@std/test/test.ms"

interface Increment:
    fn apply(value: Int) Int

type Offset:
    delta: Int

impl Increment for Offset:
    fn apply(value: Int) Int:
        return value + self.delta

fn use_increment(operation: Increment) Int:
    return operation.apply(4)

test "explicit contract conversion":
    let offset = Offset(1)
    let operation: Increment = offset
    let same_view: Increment = operation
    try expect_equal(use_increment(same_view), 5)
