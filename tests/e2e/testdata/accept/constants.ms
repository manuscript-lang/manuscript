import {expect_equal, expect_true} from "@std/testing.ms"

let LIMIT = 10
let DOUBLE = LIMIT * 2
let NAMES: List[String] = ["a", "b"]
let GREETING = "limit {LIMIT}"
let NOTHING: Optional[Int] = none
let from = 4

fn limit_plus(extra: Int) -> Int:
    return LIMIT + extra

test "constants stand for their initializers":
    DOUBLE | try expect_equal(expected: 20)
    limit_plus(extra: 1) | try expect_equal(expected: 11)
    GREETING | try expect_equal(expected: "limit 10")
    (NOTHING.is_none()) | try expect_true
    from | try expect_equal(expected: 4)

test "each use starts from a fresh collection":
    var names = NAMES
    names = names.append(value: "c")
    (names.length() == 3 and NAMES.length() == 2) | try expect_true

test "a local binding shadows a constant":
    let LIMIT = 3
    LIMIT | try expect_equal(expected: 3)

type Phase:
    case Idle
    case Active(count: Int)

let START = Phase.Idle
let NEXT: Phase = Idle

fn phase_name(phase: Phase) -> String:
    match phase:
        Idle:
            return "idle"
        Active(count):
            return "active {count}"

test "a qualified payloadless case is a constant":
    try expect_true(
        (
            phase_name(phase: START) == "idle"
            and phase_name(phase: NEXT) == "idle"
        )
    )
