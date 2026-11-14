// conform: tags=control-flow,interfaces,modules,records,stdlib-testing,testing,tier-core,try-result
// conform: phase=test
// conform: origin=tests/e2e/testdata/stdlib/testing-fixture.ms
import TestHooks, expect_equal from "@std/test/test.ms"

type Counter:
    value: Int

fn make_fixture() Counter:
    return Counter(0)

fn var Counter.before_each() Unit!:
    self.value = 1

fn var Counter.after_each() Unit!:
    self.value = 10

test "first fixture use":
    expect_equal(fixture.value, 1)?

test "second fixture use starts from clean state":
    expect_equal(fixture.value, 1)?
