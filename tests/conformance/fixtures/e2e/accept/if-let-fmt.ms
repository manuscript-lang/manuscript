# conform: tags=control-flow,formatter,interpolation,lists,modules,mutation,optional,parser,stdlib-errors,stdlib-testing,strings,testing,tier-stdlib,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/accept/if-let.ms
import {TextError} from "@std/errors.ms"
import {expect_true, fail} from "@std/testing.ms"

fn describe(name: Optional[String]) String:
    if let value = name:
        return "Hello, " + value
    else:
        return "Hello!"

fn total(items: List[Optional[Int]]) Int:
    var sum = 0
    for item in items:
        if let value = item:
            sum = sum + value
    return sum

fn check(value: Bool, message: String) Result[Unit, Error]:
    (value) | try expect_true
    return ok(unit)

test "if let unwraps a present optional":
    if let value = [4, 5].first():
        (try check(value: value == 4, message: "wrong value"))
    else:
        try fail(message: "expected some")

test "if let takes else when absent and keeps falsy payloads":
    (try check(value: describe(none) == "Hello!", message: "none"))
    (try check(value: describe(some("Ada")) == "Hello, Ada", message: "some"))
    let items: List[Optional[Int]] = [some(1), none, some(0), some(2)]
    (try check(value: total(items) == 3, message: "total"))
    let empty: List[Int] = []
    if let value = empty.first(): return fail(message: "unexpected {value}")

fn parse(text: String) Result[Int, TextError]:
    if text == "":
        return error(TextError("empty"))

    return ok(text.length())

test "if let unwraps an ok result and takes else on error":
    if let value = parse("abc"):
        (try check(value: value == 3, message: "ok value"))
    else:
        try fail(message: "expected ok")

    if let value = parse(""):
        try fail(message: "unexpected {value}")
    else:
        (try check(value: true, message: "error branch"))
