import panic from "@std/faults.ms"

let LIMIT = 10
let DOUBLE = LIMIT * 2
let NAMES: List[String] = ["a", "b"]
let GREETING = "limit {LIMIT}"
let NOTHING: Optional[Int] = none
let from = 4

fn limit_plus(extra: Int) Int:
    return LIMIT + extra

test "constants stand for their initializers":
    if not (DOUBLE == 20):
        return panic("check failed")
    if not (limit_plus(1) == 11):
        return panic("check failed")
    if not (GREETING == "limit 10"):
        return panic("check failed")
    if not (NOTHING.is_none()):
        return panic("check failed")
    if not (from == 4):
        return panic("check failed")

test "each use starts from a fresh collection":
    var names = NAMES
    names = names.append("c")
    if not (names.length() == 3 and NAMES.length() == 2):
        return panic("check failed")

test "a local binding shadows a constant":
    let LIMIT = 3
    if not (LIMIT == 3):
        return panic("check failed")

type Phase:
    case Idle
    case Active(count: Int)

let START = Phase.Idle
let NEXT: Phase = Idle

fn phase_name(phase: Phase) String:
    match phase:
        Idle:
            return "idle"
        Active(count):
            return "active {count}"

test "a qualified payloadless case is a constant":
    if not (phase_name(START) == "idle" and phase_name(NEXT) == "idle"):
        return panic("check failed")
