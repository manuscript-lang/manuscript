# conform: tags=alternatives,formatter,match,modules,parser,records,stdlib-testing,strings,testing,tier-core,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/accept/cl-07.ms
from "@std/testing.ms" import expect_equal

type Outcome:
    case Ready(value: Int)
    case Failed(reason: String)

def score(outcome: Outcome) -> Int:
    match outcome:
        case Ready(value):
            return value
        case Failed(_):
            return 0

test "alternative result":
    try expect_equal(score(Outcome.Ready(8)), 8)
    try expect_equal(score(Outcome.Failed("unavailable")), 0)
