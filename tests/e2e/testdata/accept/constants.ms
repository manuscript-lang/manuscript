import panic from "@std/faults.ms"

let LIMIT = 10
let DOUBLE = LIMIT * 2
let NAMES: List[String] = ["a", "b"]
let GREETING = "limit {LIMIT}"
let NOTHING: Optional[Int] = none
let from = 4

fn limit_plus(extra: Int) -> Int:
    return LIMIT + extra

test "constants stand for their initializers":
    if not (DOUBLE == 20):
        return panic(message: "check failed")

    if not (limit_plus(extra: 1) == 11):
        return panic(message: "check failed")

    if not (GREETING == "limit 10"):
        return panic(message: "check failed")

    if not (NOTHING.is_none()):
        return panic(message: "check failed")

    if not (from == 4):
        return panic(message: "check failed")

test "each use starts from a fresh collection":
    var names = NAMES
    names = names.append(value: "c")

    if not (names.length() == 3 and NAMES.length() == 2):
        return panic(message: "check failed")

test "a local binding shadows a constant":
    let LIMIT = 3

    if not (LIMIT == 3):
        return panic(message: "check failed")
