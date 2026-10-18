import {TestHooks, expect_equal} from "@std/testing.ms"

type Counter:
    value: Int

fn make_fixture() -> Counter:
    return Counter(value: 0)

impl TestHooks for Counter:
    fn before_each() -> Unit:
        self.value = 1

    fn after_each() -> Unit:
        self.value = 10

test "first fixture use":
    fixture.value | try expect_equal(expected: 1)

test "second fixture use starts from clean state":
    fixture.value | try expect_equal(expected: 1)
