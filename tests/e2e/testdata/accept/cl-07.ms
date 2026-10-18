import panic from "@std/faults.ms"

type Outcome:
    case Ready(value: Int)
    case Failed(reason: String)

fn score(outcome: Outcome) Int:
    match outcome:
        Ready(value):
            return value
        Failed(_):
            return 0

test "alternative result":
    if not (score(Outcome.Ready(8)) == 8):
        return panic("check failed")
    if not (score(Outcome.Failed("unavailable")) == 0):
        return panic("check failed")
