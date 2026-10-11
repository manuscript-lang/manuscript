import List from "@std/collections.ms"

type State:
    case Ready
    case Waiting

fn loop(state: State) -> Int:
    var count = 0
    for value in [1, 2, 3]:
        count = count + 1
        match state:
            Ready:
                break
            Waiting:
                continue
        count = count + 100
    return count

test "match controls nearest source loop":
    assert loop(state: State.Ready) == 1
    assert loop(state: State.Waiting) == 3
