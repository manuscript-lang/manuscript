import {expect_equal, expect_false} from "@std/testing.ms"

fn parse(text: String) -> Result[Int, String]:
    if text == "-":
        return error("n")
    if text == "big":
        return error("big")

    return ok(text.length())

fn double(n: Int) -> Int: n * 2

fn add(n: Int, by: Int) -> Int: n + by

fn check(n: Int) -> Result[Int, String]:
    if n > 100:
        return error("big")

    return ok(n)

fn flow(text: String) -> Result[Int, String]:
    let n = try parse(text)
        | double
        | add(by: 3)
        | try check
    return ok(n)

fn bare(text: String) -> Result[Int, String]:
    return ok(try parse(text) | double | check | try)

fn describe(text: String) -> Result[String, String]:
    let label = try parse(text)
        | try check
        | add(by: 1)
        .to_string(radix: 10)
    return ok(label)

fn order(log: List[String]) -> Int:
    return trace(log, "a") | add(by: trace(log, "b")) | double

fn trace(log: List[String], name: String) -> Int:
    log.append(name)
    return 1

fn code(r: Result[Int, String]) -> Int:
    return match r:
        ok(v): v
        error(cause): 0 - cause.length()

test "pipe steps call functions with the value first":
    code(flow("abc")) | try expect_equal(expected: 9)
    code(flow("-")) | try expect_equal(expected: -1)
    code(flow("big")) | try expect_equal(expected: -3)

test "bare try unwraps the value so far":
    bare("abc").unwrap() | try expect_equal(expected: 6)
    code(bare("-")) | try expect_equal(expected: -1)

test "pipe passes a Result through a step without try":
    let r = parse("abcd") | .map(fn(value: Int) -> Int: value * 2)
    r.unwrap() | try expect_equal(expected: 8)

test "leading dot after a step applies to its result":
    describe("xy").unwrap() | try expect_equal(expected: "3")

test "head is evaluated before step arguments":
    let log: List[String] = []
    order(log) | try expect_equal(expected: 4)
    (log.at(0).unwrap() != "a" or log.at(1).unwrap() != "b") | try expect_false

test "dot steps call methods on the value":
    let size = "abc" | .length() | double
    size | try expect_equal(expected: 6)
