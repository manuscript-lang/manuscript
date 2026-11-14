// conform: tags=control-flow,interfaces,modules,records,stdlib-testing,testing,tier-core,try-result
// conform: phase=test
// conform: origin=documentation/learn/testing.md:96
import TestHooks, expect_equal from "@std/test/test.ms"

type Counter:
    count: Int

fn make_fixture() Counter:
    return Counter(0)

fn var Counter.before_each() Unit!:
    self.count = 0

test "increments":
    fixture.count += 1
    expect_equal(fixture.count, 1)?

test "starts fresh":
    expect_equal(fixture.count, 0)?
