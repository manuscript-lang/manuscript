// conform: tags=closures,control-flow,faults,formatter,lists,modules,parser,stdlib-errors,stdlib-testing,strings,testing,tier-stdlib,try-result,scope-cleanup
// conform: phase=parse
// conform: origin=tests/e2e/testdata/accept/pipe-flow.ms
import expect_equal, expect_false from "@std/test/test.ms"

fn parse(text: String) Int!Error:
    if text == "-":
        return error(Error("n"))
    if text == "big":
        return error(Error("big"))

    return ok(text.length())

fn double(n: Int) Int: n * 2

fn add(n: Int, by: Int) Int: n + by

fn check(n: Int) Int!Error:
    if n > 100:
        return error(Error("big"))

    return ok(n)

fn flow(text: String) Int!Error:
    n := parse(text)?
        | double
        | add(3)
        | check?
    return ok(n)

fn bare(text: String) Int!Error:
    return ok(parse(text)? | double | check?)

fn describe(text: String) String!Error:
    label := parse(text)?
        | check?
        | add(1)
        .to_string_radix(10)
    return ok(label)

fn order(var log: List[String]) Int:
    return trace(var log, "a") | add(trace(var log, "b")) | double

fn trace(var log: List[String], name: String) Int:
    log.append(name)
    return 1

fn code(r: Int!Error) Int:
    if v := r:
        return v

    return 0 - r.err().message.length()

test "pipe steps call functions with the value first":
    expect_equal(code(flow("abc")), 9)?
    expect_equal(code(flow("-")), -1)?
    expect_equal(code(flow("big")), -3)?

test "bare unwraps? the value so far":
    expect_equal(bare("abc").get(), 6)?
    expect_equal(code(bare("-")), -1)?

test "pipe passes a Result through a step without try":
    r := parse("abcd") | .map(fn(value: Int) Int: value * 2)
    expect_equal(r.get(), 8)?

test "leading dot after a step applies to its result":
    expect_equal(describe("xy").get(), "3")?

test "head is evaluated before step arguments":
    var log: List[String] = []
    expect_equal(order(var log), 4)?
    expect_false(log.get(0) != "a" or log.get(1) != "b")?

test "dot steps call methods on the value":
    size := "abc" | .length() | double
    expect_equal(size, 6)?
