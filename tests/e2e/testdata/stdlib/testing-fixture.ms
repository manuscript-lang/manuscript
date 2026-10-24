from "@std/testing.ms" import TestHooks, expect_equal

type Counter:
    value: Int

def make_fixture() -> Counter:
    return Counter(0)

impl TestHooks for Counter:
    var def before_each() -> Unit:
        self.value = 1

    var def after_each() -> Unit:
        self.value = 10

test "first fixture use":
    try expect_equal(fixture.value, 1)

test "second fixture use starts from clean state":
    try expect_equal(fixture.value, 1)
