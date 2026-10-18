import {expect_equal, expect_false} from "@std/testing.ms"

fn parse(text: String) Result[Int, String]:
    if text == "-":
        return error("n")
    if text == "big":
        return error("big")

    return ok(text.length())

fn double(n: Int) Int: n * 2

fn add(n: Int, by: Int) Int: n + by

fn check(n: Int) Result[Int, String]:
    if n > 100:
        return error("big")

    return ok(n)

fn flow(text: String) Result[Int, String]:
    let n = try parse(text)
        | double
        | add(3)
        | try check
    return ok(n)

fn bare(text: String) Result[Int, String]:
    return ok(try parse(text) | double | check | try)

fn describe(text: String) Result[String, String]:
    let label = try parse(text)
        | try check
        | add(1)
        .to_string_radix(10)
    return ok(label)

fn order(log: List[String]) Int:
    return trace(log, "a") | add(trace(log, "b")) | double

fn trace(log: List[String], name: String) Int:
    log.append(name)
    return 1

fn code(r: Result[Int, String]) Int:
    if let v = r:
        return v

    return 0 - r.err().length()

test "pipe steps call functions with the value first":
    try expect_equal(code(flow("abc")), 9)
    try expect_equal(code(flow("-")), -1)
    try expect_equal(code(flow("big")), -3)

test "bare try unwraps the value so far":
    try expect_equal(bare("abc").get(), 6)
    try expect_equal(code(bare("-")), -1)

test "pipe passes a Result through a step without try":
    let r = parse("abcd") | .map(fn(value: Int) Int: value * 2)
    try expect_equal(r.get(), 8)

test "leading dot after a step applies to its result":
    try expect_equal(describe("xy").get(), "3")

test "head is evaluated before step arguments":
    let log: List[String] = []
    try expect_equal(order(log), 4)
    try expect_false(log.at(0).get() != "a" or log.at(1).get() != "b")

test "dot steps call methods on the value":
    let size = "abc" | .length() | double
    try expect_equal(size, 6)
