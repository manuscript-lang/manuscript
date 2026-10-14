import panic from "@std/faults.ms"

import List from "@std/collections.ms"

fn parse(n: Int) -> Result[Int, String]:
    if n < 0:
        return error("neg")

    return ok(n)

fn bound(n: Int) -> Result[Int, String]:
    let v = try parse(n: n)
    return ok(v + 1)

fn reassigned(n: Int) -> Result[Int, String]:
    var total = 1
    total = try parse(n: n)
    return ok(total * 2)

fn check(n: Int) -> Result[Unit, String]:
    if n < 0:
        return error("neg")

    return ok(unit)

fn discarded(n: Int) -> Result[Int, String]:
    try check(n: n)
    return ok(7)

fn code(r: Result[Int, String]) -> Int:
    return match r:
        ok(v): v
        error(e): -1

fn nested(n: Int) -> Result[Int, String]:
    return ok((try parse(n: n)) + (try parse(n: n - 5)))

fn chained(n: Int) -> Result[Int, String]:
    let a = try bound(n: n)
    let b = try reassigned(n: a - 10)
    return ok(b)

fn in_loop(values: List[Int]) -> Result[Int, String]:
    var sum = 0

    for v in values:
        sum = sum + (try parse(n: v))

    return ok(sum)

fn in_lambda(n: Int) -> Result[Int, String]:
    let inner = fn() -> Result[Int, String]:
        let v = try parse(n: n)
        return ok(v * 10)
    let r = try inner()
    return ok(r + 1)

test "statement try returns the error and binds the value":
    if not (code(r: bound(n: 4)) == 5):
        return panic(message: "bound ok")
    if not (code(r: bound(n: -1)) == -1):
        return panic(message: "bound error")
    if not (code(r: reassigned(n: 3)) == 6):
        return panic(message: "assign ok")
    if not (code(r: reassigned(n: -2)) == -1):
        return panic(message: "assign error")
    if not (code(r: discarded(n: 1)) == 7):
        return panic(message: "discard ok")
    if not (code(r: discarded(n: -1)) == -1):
        return panic(message: "discard error")

test "try nested in expressions and chains still propagates":
    if not (code(r: nested(n: 6)) == 7):
        return panic(message: "nested ok")
    if not (code(r: nested(n: 2)) == -1):
        return panic(message: "nested error")
    if not (code(r: chained(n: 12)) == 6):
        return panic(message: "chained ok")
    if not (code(r: chained(n: 3)) == -1):
        return panic(message: "chained error")

test "try in loops and lambdas":
    if not (code(r: in_loop(values: [1, 2, 3])) == 6):
        return panic(message: "loop ok")
    if not (code(r: in_loop(values: [1, -2, 3])) == -1):
        return panic(message: "loop error")
    if not (code(r: in_lambda(n: 2)) == 21):
        return panic(message: "lambda ok")
    if not (code(r: in_lambda(n: -2)) == -1):
        return panic(message: "lambda error")
