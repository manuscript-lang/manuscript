import panic from "@std/faults.ms"

type State:
    case Ready
    case Waiting

fn loop(state: State) Int:
    var count = 0

    for value in [1, 2, 3]:
        count += 1

        match state:
            Ready:
                break
            Waiting:
                continue

        count += 100

    return count

test "match controls nearest source loop":
    if not (loop(State.Ready) == 1):
        return panic("check failed")
    if not (loop(State.Waiting) == 3):
        return panic("check failed")
