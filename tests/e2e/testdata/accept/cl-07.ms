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
    assert score(outcome: Outcome.Ready(value: 8)) == 8
    assert score(outcome: Outcome.Failed(reason: "unavailable")) == 0
