import panic from "@std/faults.ms"

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
        | add(by: 3)
        | try check
    return ok(n)

fn bare(text: String) Result[Int, String]:
    return ok(try parse(text) | double | check | try)

fn describe(text: String) Result[String, String]:
    let label = try parse(text)
        | try check
        | add(by: 1)
        .to_string_radix(radix: 10)
    return ok(label)

fn order(log: List[String]) Int:
    return trace(log, "a") | add(by: trace(log, "b")) | double

fn trace(log: List[String], name: String) Int:
    log.append(name)
    return 1

fn code(r: Result[Int, String]) Int:
    if r.is_error():
        return 0 - r.unwrap_error().length()

    return r.unwrap()

test "pipe steps call functions with the value first":
    if code(flow("abc")) != 9:
        return panic("flow ok")
    if code(flow("-")) != -1:
        return panic("flow first failure")
    if code(flow("big")) != -3:
        return panic("flow later failure")

test "bare try unwraps the value so far":
    if bare("abc").unwrap() != 6:
        return panic("bare ok")
    if code(bare("-")) != -1:
        return panic("bare early return")

test "pipe passes a Result through a step without try":
    let r = parse("abcd") | .map(fn(value: Int) Int: value * 2)
    if r.unwrap() != 8:
        return panic("map step")

test "leading dot after a step applies to its result":
    if describe("xy").unwrap() != "3":
        return panic("describe")

test "head is evaluated before step arguments":
    let log: List[String] = []
    if order(log) != 4:
        return panic("order value")
    if log.at(0).unwrap() != "a" or log.at(1).unwrap() != "b":
        return panic("order trace")

test "dot steps call methods on the value":
    let size = "abc" | .length() | double
    if size != 6:
        return panic("method step")
