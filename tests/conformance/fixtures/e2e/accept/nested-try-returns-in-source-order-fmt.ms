# conform: tags=control-flow,faults,formatter,interpolation,lists,modules,mutation,parser,stdlib-errors,stdlib-testing,strings,testing,tier-stdlib,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/accept/nested-try-returns-in-source-order.ms
import TextError from "@std/core.ms"
import expect_true from "@std/test.ms"

fn step(var log: List[String], name: String, n: Int) Int!TextError:
    log.append(value: name.clone())
    if n < 0:
        return error(cause: TextError(name))

    return ok(value: n)

fn add(x: Int, y: Int) Int:
    return x + y

fn sum(var log: List[String], a: Int, b: Int) Int!TextError:
    let v = (
        (try step(log: var log, name: "a", n: a))
        + (try step(log: var log, name: "b", n: b))
    )
    log.append(value: "done")
    return ok(value: v)

fn arguments(var log: List[String], a: Int, b: Int) Int!TextError:
    return ok(
        value: add(
            x: try step(log: var log, name: "x", n: a),
            y: try step(log: var log, name: "y", n: b)
        )
    )

fn effect_first(var log: List[String], a: Int) Int!TextError:
    log.append(value: "before")

    let v = add(x: 1, y: try step(log: var log, name: "s", n: a))
    return ok(value: v)

fn loop(var log: List[String], n: Int) Int!TextError:
    var total = 0
    var i = 0

    while i < n:
        total = total + try step(log: var log, name: "l", n: 1 - i)
        i = i + 1

    return ok(value: total)

fn joined(var log: List[String]) String!TextError:
    return ok(
        value: "{try step(log: var log, name: "p", n: 1)}-{try step(log: var log, name: "q", n: -1)}"
    )

fn text(log: List[String]) String:
    return log.join(separator: ",")

test "nested try":
    var first = List[String]()
    try expect_true((sum(log: var first, a: 1, b: 2).get() == 3))
    try expect_true((text(log: first) == "a,b,done"))

    var second = List[String]()
    try expect_true((sum(log: var second, a: -1, b: 2).err().message() == "a"))
    try expect_true((text(log: second) == "a"))

    var third = List[String]()
    try expect_true((arguments(log: var third, a: 1, b: -1).err().message() == "y"))
    try expect_true((text(log: third) == "x,y"))

    var fourth = List[String]()
    try expect_true((effect_first(log: var fourth, a: -1).err().message() == "s"))
    try expect_true((text(log: fourth) == "before,s"))

    var fifth = List[String]()
    try expect_true((loop(log: var fifth, n: 5).err().message() == "l"))
    try expect_true((text(log: fifth) == "l,l,l"))

    var sixth = List[String]()
    try expect_true((joined(log: var sixth).err().message() == "q"))
    try expect_true((text(log: sixth) == "p,q"))
