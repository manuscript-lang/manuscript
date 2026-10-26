from "@std/core.ms" import TextError
from "@std/testing.ms" import expect_equal, fail
from "@std/io.ms" import stderr
from "@std/io.ms" import stdout
from "@std/io.ms" import WriteStream
from "@std/core.ms" import Closeable

type Resource:
    label: String
    output: WriteStream

impl Closeable for Resource:
    var def close() -> Unit:
        self.output.write(data: f"close {self.label}\n")

type Pair:
    first: Int
    second: Int

def report(var output: WriteStream, label: String, value: Int) -> Int:
    output.write(data: f"{label}\n")
    return value

def combine(first: Int, second: Int) -> Int:
    return first + second

def select(var output: WriteStream) -> Callable[[Int, Int], Int]:
    output.write(data: "callable\n")
    return combine

def early(var output: WriteStream) -> Int:
    with let outer = Resource(label: "outer", output: stdout()):
        with let inner = Resource(label: "inner", output: stdout()):
            return report(output: var output, label: "return value", value: 5)

def failure() -> Result[Int, TextError]:
    return error(TextError("expected"))

def propagate(output: WriteStream) -> Result[Int, TextError]:
    with let resource = Resource(label: "propagation", output: output):
        let number = try failure()
        return ok(number)

def iterable(var output: WriteStream) -> List[Int]:
    output.write(data: "iterable\n")
    return [1, 2]

def exercise() -> Result[Int, Error]:
    var chosen = stdout()
    var second_out = stdout()
    var first_out = stdout()
    let total = select(output: var chosen)(
        report(output: var second_out, label: "second", value: 2),
        report(output: var first_out, label: "first", value: 1)
    )
    total | try expect_equal(3)

    var pair_second_out = stdout()
    var pair_first_out = stdout()
    let pair = Pair(
        second: report(
            output: var pair_second_out, label: "pair second", value: 2
        ),
        first: report(output: var pair_first_out, label: "pair first", value: 1)
    )
    (pair.first + pair.second) | try expect_equal(3)
    with let resource = Resource(label: "normal", output: stdout()):
        let _completed = ()
    stdout().write(data: "after normal\n")

    var count = 0

    while count < 2:
        with let resource = Resource(label: "iteration", output: stdout()):
            count = count + 1
            continue

    var iterable_out = stdout()
    for value in iterable(output: var iterable_out):
        with let resource = Resource(label: "break", output: stdout()):
            break

    match propagate(output: stdout()):
        case ok(_):
            try fail(message: "Unexpected case")
        case error(_):
            let _completed = ()

    var early_out = stdout()
    early(output: var early_out) | try expect_equal(5)
    stdout().write(data: "finished\n")
    return ok(0)

export def main() -> Int:
    match exercise():
        case ok(status): return status
        case error(cause):
            let _written = stderr().write(f"{cause.message()}\n")
            return 1
