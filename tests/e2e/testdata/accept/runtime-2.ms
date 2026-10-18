import {expect_equal} from "@std/testing.ms"

type Items:
    count: Int

type Outcome:
    case Value(value: Int)

fn compute(value: Int) Int:
    return value

fn ordinary() Outcome:
    return Outcome.Value(compute(3))

test "non-prelude spellings are ordinary names":
    try expect_equal(Items(2).count, 2)
    let forward = compute
    try expect_equal(forward(4), 4)

    match ordinary():
        Value(value):
            try expect_equal(value, 3)
