from "@std/testing.ms" import expect_equal

interface Increment:
    def apply(value: Int) -> Int

type Offset:
    delta: Int

impl Increment for Offset:
    def apply(value: Int) -> Int:
        return value + self.delta

def use_increment(operation: Increment) -> Int:
    return operation.apply(4)

test "explicit contract conversion":
    let offset = Offset(1)
    let operation = Increment(offset)
    let same_view = Increment(operation)
    try expect_equal(use_increment(same_view), 5)
