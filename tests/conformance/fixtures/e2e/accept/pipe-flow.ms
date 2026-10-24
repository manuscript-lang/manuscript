# conform: tags=closures,control-flow,faults,lists,modules,stdlib-errors,stdlib-testing,strings,testing,tier-stdlib,try-result,with-cleanup
# conform: phase=test
# conform: origin=tests/e2e/testdata/accept/pipe-flow.ms
from "@std/core.ms" import TextError
from "@std/testing.ms" import expect_equal, expect_false

def parse(text: String) -> Result[Int, TextError]:
    if text == "-":
        return error(TextError("n"))
    if text == "big":
        return error(TextError("big"))

    return ok(text.length())

def double(n: Int) -> Int: n * 2

def add(n: Int, by: Int) -> Int: n + by

def check(n: Int) -> Result[Int, TextError]:
    if n > 100:
        return error(TextError("big"))

    return ok(n)

def flow(text: String) -> Result[Int, TextError]:
    let n = try parse(text)
        | double
        | add(3)
        | try check
    return ok(n)

def bare(text: String) -> Result[Int, TextError]:
    return ok(try parse(text) | double | check | try)

def describe(text: String) -> Result[String, TextError]:
    let label = try parse(text)
        | try check
        | add(1)
        .to_string_radix(10)
    return ok(label)

def order(var log: List[String]) -> Int:
    return trace(var log, "a") | add(trace(var log, "b")) | double

def trace(var log: List[String], name: String) -> Int:
    log.append(name)
    return 1

def code(r: Result[Int, TextError]) -> Int:
    if let v = r:
        return v

    return 0 - r.err().message().length()

test "pipe steps call functions with the value first":
    try expect_equal(code(flow("abc")), 9)
    try expect_equal(code(flow("-")), -1)
    try expect_equal(code(flow("big")), -3)

test "bare try unwraps the value so far":
    try expect_equal(bare("abc").get(), 6)
    try expect_equal(code(bare("-")), -1)

test "pipe passes a Result through a step without try":
    let r = parse("abcd") | .map(lambda (value: Int) -> Int: value * 2)
    try expect_equal(r.get(), 8)

test "leading dot after a step applies to its result":
    try expect_equal(describe("xy").get(), "3")

test "head is evaluated before step arguments":
    var log: List[String] = []
    try expect_equal(order(var log), 4)
    try expect_false(log.get(0) != "a" or log.get(1) != "b")

test "dot steps call methods on the value":
    let size = "abc" | .length() | double
    try expect_equal(size, 6)
