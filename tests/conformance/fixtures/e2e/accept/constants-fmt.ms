# conform: tags=alternatives,control-flow,formatter,interpolation,lists,match,modules,mutation,optional,parser,records,stdlib-testing,strings,testing,tier-core,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/accept/constants.ms
from "@std/testing.ms" import expect_equal, expect_false

let LIMIT = 10
let DOUBLE = LIMIT * 2
let NAMES: List[String] = ["a", "b"]
let GREETING = f"limit {LIMIT}"
let NOTHING: Optional[Int] = none
let from = 4

def limit_plus(extra: Int) -> Int:
    return LIMIT + extra

test "constants stand for their initializers":
    try expect_equal(DOUBLE, 20)
    try expect_equal(limit_plus(1), 11)
    try expect_equal(GREETING, "limit 10")
    try expect_false(not (NOTHING.is_none()))
    try expect_equal(from, 4)

test "each use starts from a fresh collection":
    var names = NAMES
    names.append("c")
    try expect_false(not (names.length() == 3 and NAMES.length() == 2))

test "a local binding shadows a constant":
    let LIMIT = 3
    try expect_equal(LIMIT, 3)

type Phase:
    case Idle
    case Active(count: Int)

let START = Phase.Idle
let NEXT: Phase = Idle

def phase_name(phase: Phase) -> String:
    match phase:
        case Idle:
            return "idle"
        case Active(count):
            return f"active {count}"

test "a qualified payloadless case is a constant":
    try expect_false(not (phase_name(START) == "idle" and phase_name(NEXT) == "idle"))
