import {expect_equal} from "@std/testing.ms"

interface Increment:
    fn apply(value: Int) -> Int

type Offset:
    delta: Int

impl Increment for Offset:
    fn apply(value: Int) -> Int:
        return value + self.delta

fn use_increment(operation: Increment) -> Int:
    return operation.apply(value: 4)

test "explicit contract conversion":
    let offset = Offset(1)
    let operation = Increment(offset)
    let same_view = Increment(operation)
    use_increment(operation: same_view) | try expect_equal(expected: 5)
