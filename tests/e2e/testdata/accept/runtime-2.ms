import {expect_equal} from "@std/testing.ms"

type List:
    count: Int

type Result:
    case Value(value: Int)

fn compute(value: Int) -> Int:
    return value

fn ordinary() -> Result:
    return Result.Value(compute(value: 3))

test "standard spellings are ordinary names":
    List(2).count | try expect_equal(expected: 2)
    let forward = compute
    forward(value: 4) | try expect_equal(expected: 4)

    match ordinary():
        Value(value):
            try expect_equal(value, 3)
