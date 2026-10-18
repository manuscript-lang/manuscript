import {expect_true} from "@std/testing.ms"

fn step(log: List[String], name: String, n: Int) Result[Int, String]:
    log.append(value: name)
    if n < 0:
        return error(cause: name)

    return ok(value: n)

fn add(x: Int, y: Int) Int:
    return x + y

fn sum(log: List[String], a: Int, b: Int) Result[Int, String]:
    let v = (
        (try step(log: log, name: "a", n: a))
        + (try step(log: log, name: "b", n: b))
    )
    log.append(value: "done")
    return ok(value: v)

fn arguments(log: List[String], a: Int, b: Int) Result[Int, String]:
    return ok(
        value: add(
            x: try step(log: log, name: "x", n: a),
            y: try step(log: log, name: "y", n: b)
        )
    )

fn effect_first(log: List[String], a: Int) Result[Int, String]:
    log.append(value: "before")
    let v = add(x: 1, y: try step(log: log, name: "s", n: a))
    return ok(value: v)

fn loop(log: List[String], n: Int) Result[Int, String]:
    var total = 0
    var i = 0

    while i < n:
        total = total + try step(log: log, name: "l", n: 1 - i)
        i = i + 1

    return ok(value: total)

fn joined(log: List[String]) Result[String, String]:
    return ok(
        value: "{try step(log: log, name: "p", n: 1)}-{try step(log: log, name: "q", n: -1)}"
    )

fn text(log: List[String]) String:
    return log.join(separator: ",")

test "nested try":
    let first = List[String]()
    try expect_true((sum(log: first, a: 1, b: 2).get() == 3))
    try expect_true((text(log: first) == "a,b,done"))
    let second = List[String]()
    try expect_true((sum(log: second, a: -1, b: 2).err() == "a"))
    try expect_true((text(log: second) == "a"))
    let third = List[String]()
    try expect_true((arguments(log: third, a: 1, b: -1).err() == "y"))
    try expect_true((text(log: third) == "x,y"))
    let fourth = List[String]()
    try expect_true((effect_first(log: fourth, a: -1).err() == "s"))
    try expect_true((text(log: fourth) == "before,s"))
    let fifth = List[String]()
    try expect_true((loop(log: fifth, n: 5).err() == "l"))
    try expect_true((text(log: fifth) == "l,l,l"))
    let sixth = List[String]()
    try expect_true((joined(log: sixth).err() == "q"))
    try expect_true((text(log: sixth) == "p,q"))
