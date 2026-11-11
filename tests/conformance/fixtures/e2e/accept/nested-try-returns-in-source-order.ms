// conform: tags=control-flow,faults,interpolation,lists,modules,mutation,stdlib-errors,stdlib-testing,strings,testing,tier-stdlib,try-result
// conform: phase=test
// conform: origin=tests/e2e/testdata/accept/nested-try-returns-in-source-order.ms
import expect_true from "@std/test/test.ms"

fn step(var log: List[String], name: String, n: Int) Int!Error:
    log.append(value: name.clone())
    if n < 0:
        return error(cause: Error(name))

    return ok(value: n)

fn add(x: Int, y: Int) Int:
    return x + y

fn sum(var log: List[String], a: Int, b: Int) Int!Error:
    v := (
        (step(log: var log, name: "a", n: a)?)
        + (step(log: var log, name: "b", n: b)?)
    )
    log.append(value: "done")
    return ok(value: v)

fn arguments(var log: List[String], a: Int, b: Int) Int!Error:
    return ok(
        value: add(
            x: step(log: var log, name: "x", n: a)?,
            y: step(log: var log, name: "y", n: b)?
        )
    )

fn effect_first(var log: List[String], a: Int) Int!Error:
    log.append(value: "before")

    v := add(x: 1, y: step(log: var log, name: "s", n: a)?)
    return ok(value: v)

fn loop(var log: List[String], n: Int) Int!Error:
    var total = 0
    var i = 0

    while i < n:
        total = total + step(log: var log, name: "l", n: 1 - i)?
        i = i + 1

    return ok(value: total)

fn joined(var log: List[String]) String!Error:
    return ok(
        value: "{step(log: var log, name: "p", n: 1)?}-{step(log: var log, name: "q", n: -1)?}"
    )

fn text(log: List[String]) String:
    return log.join(separator: ",")

test "nested try":
    var first = List[String]()
    expect_true((sum(log: var first, a: 1, b: 2).get() == 3))?
    expect_true((text(log: first) == "a,b,done"))?

    var second = List[String]()
    expect_true((sum(log: var second, a: -1, b: 2).err().message == "a"))?
    expect_true((text(log: second) == "a"))?

    var third = List[String]()
    expect_true((arguments(log: var third, a: 1, b: -1).err().message == "y"))?
    expect_true((text(log: third) == "x,y"))?

    var fourth = List[String]()
    expect_true((effect_first(log: var fourth, a: -1).err().message == "s"))?
    expect_true((text(log: fourth) == "before,s"))?

    var fifth = List[String]()
    expect_true((loop(log: var fifth, n: 5).err().message == "l"))?
    expect_true((text(log: fifth) == "l,l,l"))?

    var sixth = List[String]()
    expect_true((joined(log: var sixth).err().message == "q"))?
    expect_true((text(log: sixth) == "p,q"))?
