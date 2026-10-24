# conform: tags=aliasing,closures,control-flow,interfaces,interpolation,lists,match,modules,mutation,records,stdlib-cleanup,stdlib-errors,stdlib-io,stdlib-testing,strings,tier-stdlib,try-result,with-cleanup
# conform: phase=run
# conform: origin=tests/e2e/testdata/projects/lifecycle/main.ms
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
    def close() -> Unit:
        self.output.write(data: f"close {self.label}\n")

type Pair:
    first: Int
    second: Int

def report(output: WriteStream, label: String, value: Int) -> Int:
    output.write(data: f"{label}\n")
    return value

def combine(first: Int, second: Int) -> Int:
    return first + second

def select(output: WriteStream) -> Callable[[Int, Int], Int]:
    output.write(data: "callable\n")
    return combine

def early(output: WriteStream) -> Int:
    with Resource(label: "outer", output: output) as outer:
        with Resource(label: "inner", output: output) as inner:
            return report(output: output, label: "return value", value: 5)

def failure() -> Result[Int, TextError]:
    return error(TextError("expected"))

def propagate(output: WriteStream) -> Result[Int, TextError]:
    with Resource(label: "propagation", output: output) as resource:
        let number = try failure()
        return ok(number)

def iterable(output: WriteStream) -> List[Int]:
    output.write(data: "iterable\n")
    return [1, 2]

def exercise() -> Result[Int, Error]:
    let total = select(output: stdout())(
        report(output: stdout(), label: "second", value: 2),
        report(output: stdout(), label: "first", value: 1)
    )
    total | try expect_equal(3)

    let pair = Pair(
        second: report(output: stdout(), label: "pair second", value: 2),
        first: report(output: stdout(), label: "pair first", value: 1)
    )
    (pair.first + pair.second) | try expect_equal(3)
    with Resource(label: "normal", output: stdout()) as resource:
        let completed = ()
    stdout().write(data: "after normal\n")

    var count = 0

    while count < 2:
        with Resource(label: "iteration", output: stdout()) as resource:
            count = count + 1
            continue

    for value in iterable(output: stdout()):
        with Resource(label: "break", output: stdout()) as resource:
            break

    match propagate(output: stdout()):
        case ok(_):
            try fail(message: "Unexpected case")
        case error(_):
            let completed = ()

    early(output: stdout()) | try expect_equal(5)
    stdout().write(data: "finished\n")
    return ok(0)

export def main() -> Int:
    match exercise():
        case ok(status): return status
        case error(cause):
            let written = stderr().write(f"{cause.message()}\n")
            return 1
