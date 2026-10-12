import panic from "@std/faults.ms"

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
    if not (score(outcome: Outcome.Ready(value: 8)) == 8):
        return panic(message: "check failed")
    if not (score(outcome: Outcome.Failed(reason: "unavailable")) == 0):
        return panic(message: "check failed")
