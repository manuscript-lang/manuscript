import panic from "@std/faults.ms"

fn parse(n: Int) Result[Int, String]:
    if n < 0:
        return error("neg")

    return ok(n)

fn bound(n: Int) Result[Int, String]:
    let v = try parse(n)
    return ok(v + 1)

fn reassigned(n: Int) Result[Int, String]:
    var total = 1
    total = try parse(n)
    return ok(total * 2)

fn check(n: Int) Result[Unit, String]:
    if n < 0:
        return error("neg")

    return ok(unit)

fn discarded(n: Int) Result[Int, String]:
    try check(n)
    return ok(7)

fn code(r: Result[Int, String]) Int:
    return r.get(-1)

fn nested(n: Int) Result[Int, String]:
    return ok((try parse(n)) + (try parse(n - 5)))

fn chained(n: Int) Result[Int, String]:
    let a = try bound(n)
    let b = try reassigned(a - 10)
    return ok(b)

fn in_loop(values: List[Int]) Result[Int, String]:
    var sum = 0
    for v in values:
        sum += try parse(v)
    return ok(sum)

fn in_lambda(n: Int) Result[Int, String]:
    let inner = fn() Result[Int, String]:
        let v = try parse(n)
        return ok(v * 10)
    let r = try inner()
    return ok(r + 1)

test "statement try returns the error and binds the value":
    if not (code(bound(4)) == 5):
        return panic("bound ok")
    if not (code(bound(-1)) == -1):
        return panic("bound error")
    if not (code(reassigned(3)) == 6):
        return panic("assign ok")
    if not (code(reassigned(-2)) == -1):
        return panic("assign error")
    if not (code(discarded(1)) == 7):
        return panic("discard ok")
    if not (code(discarded(-1)) == -1):
        return panic("discard error")

test "try nested in expressions and chains still propagates":
    if not (code(nested(6)) == 7):
        return panic("nested ok")
    if not (code(nested(2)) == -1):
        return panic("nested error")
    if not (code(chained(12)) == 6):
        return panic("chained ok")
    if not (code(chained(3)) == -1):
        return panic("chained error")

test "try in loops and lambdas":
    if not (code(in_loop([1, 2, 3])) == 6):
        return panic("loop ok")
    if not (code(in_loop([1, -2, 3])) == -1):
        return panic("loop error")
    if not (code(in_lambda(2)) == 21):
        return panic("lambda ok")
    if not (code(in_lambda(-2)) == -1):
        return panic("lambda error")
