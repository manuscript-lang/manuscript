# conform: tags=alternatives,control-flow,match,modules,mutation,records,stdlib-testing,testing,tier-core,try-result
# conform: phase=test
# conform: origin=tests/e2e/testdata/accept/loop-match.ms
import {expect_equal} from "@std/testing.ms"

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
    try expect_equal(loop(State.Ready), 1)
    try expect_equal(loop(State.Waiting), 3)
