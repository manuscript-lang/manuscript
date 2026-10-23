import {TextError} from "@std/core.ms"
import {expect_equal, fail} from "@std/testing.ms"
import stderr from "@std/io.ms"
import stdout from "@std/io.ms"
import WriteStream from "@std/io.ms"
import Closeable from "@std/core.ms"

type Resource:
    label: String
    output: WriteStream

impl Closeable for Resource:
    var fn close() Unit:
        self.output.write(data: "close {self.label}\n")

type Pair:
    first: Int
    second: Int

fn report(var output: WriteStream, label: String, value: Int) Int:
    output.write(data: "{label}\n")
    return value

fn combine(first: Int, second: Int) Int:
    return first + second

fn select(var output: WriteStream) fn(first: Int, second: Int) Int:
    output.write(data: "callable\n")
    return combine

fn early(output: WriteStream) Int:
    with outer = Resource(label: "outer", output: output.clone()):
        with inner = Resource(label: "inner", output: output.clone()):
            return report(output: output, label: "return value", value: 5)

fn failure() Result[Int, TextError]:
    return error(TextError("expected"))

fn propagate(output: WriteStream) Result[Int, TextError]:
    with resource = Resource(label: "propagation", output: output):
        let number = try failure()
        return ok(number)

fn iterable(var output: WriteStream) List[Int]:
    output.write(data: "iterable\n")
    return [1, 2]

fn exercise() Result[Int, Error]:
    let total = select(output: stdout())(
        second: report(output: stdout(), label: "second", value: 2),
        first: report(output: stdout(), label: "first", value: 1)
    )
    total | try expect_equal(3)

    let pair = Pair(
        second: report(output: stdout(), label: "pair second", value: 2),
        first: report(output: stdout(), label: "pair first", value: 1)
    )
    (pair.first + pair.second) | try expect_equal(3)
    with resource = Resource(label: "normal", output: stdout()):
        let completed = unit
    stdout().write(data: "after normal\n")

    var count = 0

    while count < 2:
        with resource = Resource(label: "iteration", output: stdout()):
            count = count + 1
            continue

    for value in iterable(output: stdout()):
        with resource = Resource(label: "break", output: stdout()):
            break

    match propagate(output: stdout()):
        ok(_):
            try fail(message: "Unexpected case")
        error(_):
            let completed = unit

    early(output: stdout()) | try expect_equal(5)
    stdout().write(data: "finished\n")
    return ok(0)

export fn main() Int:
    match exercise():
        ok(status): return status
        error(cause):
            let written = stderr().write("{cause.message()}\n")
            return 1
