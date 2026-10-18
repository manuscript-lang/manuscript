import {expect_equal} from "@std/testing.ms"

type Outcome:
    case Ready(value: Int)
    case Failed(reason: String)

fn score(outcome: Outcome) -> Int:
    match outcome:
        Ready(value):
            return value
        Failed(_):
            return 0

test "alternative result":
    score(outcome: Outcome.Ready(8)) | try expect_equal(expected: 8)
    score(outcome: Outcome.Failed("unavailable")) | try expect_equal(expected: 0)
