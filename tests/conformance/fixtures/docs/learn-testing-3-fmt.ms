# conform: tags=control-flow,formatter,interfaces,modules,parser,records,stdlib-testing,testing,tier-core,try-result
# conform: phase=parse
# conform: origin=documentation/learn/testing.md:96
from "@std/testing.ms" import TestHooks, expect_equal

type Counter:
    count: Int

def make_fixture() -> Counter:
    return Counter(0)

impl TestHooks for Counter:
    var def before_each() -> Unit:
        self.count = 0

test "increments":
    fixture.count += 1
    try expect_equal(fixture.count, 1)

test "starts fresh":
    try expect_equal(fixture.count, 0)
