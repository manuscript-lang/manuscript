import {expect_equal} from "@std/testing.ms"

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
    loop(state: State.Ready) | try expect_equal(expected: 1)
    loop(state: State.Waiting) | try expect_equal(expected: 3)
