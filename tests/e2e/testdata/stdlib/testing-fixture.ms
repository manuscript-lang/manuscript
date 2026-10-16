import {TestHooks, expect_equal} from "@std/testing.ms"

type Counter:
    value: Int

fn make_fixture() -> Counter:
    return Counter(value: 0)

impl TestHooks for Counter:
    fn before_each() -> Unit:
        self.value = self.value + 1

    fn after_each() -> Unit:
        self.value = self.value + 10

test "first fixture use":
    try expect_equal(fixture.value, 1)

test "second fixture use":
    try expect_equal(fixture.value, 12)
