from "@std/core.ms" import TextError
from "@std/testing.ms" import expect_true

def halve(n: Int) -> Optional[Int]:
    if n % 2 != 0:
        return none

    return some(value: n / 2)

def parse(n: Int) -> Result[Int, TextError]:
    if n < 0:
        return error(cause: TextError("negative"))

    return ok(value: n)

def matched(n: Int) -> Int:
    let found = halve(n: n)

    match found:
        case some(v):
            return v
        case none:
            return 0 - 1

def twice(n: Int) -> Int:
    let found = halve(n: n)
    var total = 0

    match found:
        case some(v):
            total = total + v
        case none:
            total = total + 100

    match found:
        case some(v):
            total = total + v
        case none:
            total = total + 1000

    return total

def results(n: Int) -> String:
    let parsed = parse(n: n)

    match parsed:
        case ok(v):
            return f"ok {v}"
        case error(cause):
            return cause.message()

def formatted(n: Int) -> String:
    let found = halve(n: n)
    return f"{found}"

def captured(n: Int) -> Int:
    let found = halve(n: n)
    let read = lambda () -> Int:
        match found:
            case some(v):
                return v
            case none:
                return 0 - 1
    return read()

test "typed alternative lets":
    try expect_true((matched(n: 8) == 4))
    try expect_true((matched(n: 7) == 0 - 1))
    try expect_true((twice(n: 8) == 8))
    try expect_true((twice(n: 7) == 1100))
    try expect_true((results(n: 3) == "ok 3"))
    try expect_true((results(n: 0 - 3) == "negative"))
    try expect_true((formatted(n: 8) == formatted(n: 8)))
    try expect_true((captured(n: 8) == 4))
    try expect_true((captured(n: 7) == 0 - 1))
