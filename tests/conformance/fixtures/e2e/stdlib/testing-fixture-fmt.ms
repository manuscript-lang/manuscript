# conform: tags=control-flow,formatter,interfaces,modules,parser,records,stdlib-testing,testing,tier-core,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/stdlib/testing-fixture.ms
import {TestHooks, expect_equal} from "@std/test.ms"

type Counter:
    value: Int

fn make_fixture() Counter:
    return Counter(0)

impl TestHooks for Counter:
    var fn before_each() Unit:
        self.value = 1

    var fn after_each() Unit:
        self.value = 10

test "first fixture use":
    try expect_equal(fixture.value, 1)

test "second fixture use starts from clean state":
    try expect_equal(fixture.value, 1)
