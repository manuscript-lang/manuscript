# conform: tags=closures,control-flow,interpolation,match,modules,mutation,optional,stdlib-errors,stdlib-testing,strings,testing,tier-stdlib,try-result
# conform: phase=test
# conform: origin=tests/e2e/testdata/accept/typed-alternative-lets-keep-semantics.ms
import expect_true from "@std/test/test.ms"

fn halve(n: Int) Int?:
    if n % 2 != 0:
        return none

    return (n / 2)

fn parse(n: Int) Int!Error:
    if n < 0:
        return error(cause: Error("negative"))

    return ok(value: n)

fn matched(n: Int) Int:
    let found = halve(n: n)

    match found:
        v:
            return v
        none:
            return 0 - 1

fn twice(n: Int) Int:
    let found = halve(n: n)
    var total = 0

    match found:
        v:
            total = total + v
        none:
            total = total + 100

    match found:
        v:
            total = total + v
        none:
            total = total + 1000

    return total

fn results(n: Int) String:
    let parsed = parse(n: n)

    match parsed:
        ok(v):
            return "ok {v}"
        error(cause):
            return cause.message

fn formatted(n: Int) String:
    let found = halve(n: n)
    return "{found}"

fn captured(n: Int) Int:
    let found = halve(n: n)
    let read = fn() Int:
        match found:
            v:
                return v
            none:
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
