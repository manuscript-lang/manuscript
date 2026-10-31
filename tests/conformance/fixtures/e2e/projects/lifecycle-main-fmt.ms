# conform: tags=aliasing,closures,control-flow,formatter,interfaces,interpolation,lists,match,modules,mutation,parser,records,stdlib-cleanup,stdlib-errors,stdlib-io,stdlib-testing,strings,tier-stdlib,try-result,scope-cleanup
# conform: phase=parse
# conform: origin=tests/e2e/testdata/projects/lifecycle/main.ms
import TextError from "@std/core.ms"
import expect_equal, fail from "@std/test.ms"
import stderr from "@std/io.ms"
import stdout from "@std/io.ms"
import WriteStream from "@std/io.ms"
import Closeable from "@std/core.ms"

type Resource:
    label: String
    output: WriteStream

impl Closeable for Resource:
    var fn close() Unit!:
        let _ = self.output.write(data: "close {self.label}\n")
        return ok(unit)

type Pair:
    first: Int
    second: Int

fn report(var output: WriteStream, label: String, value: Int) Int:
    let _ = output.write(data: "{label}\n")
    return value

fn combine(first: Int, second: Int) Int:
    return first + second

fn select(var output: WriteStream) fn(Int, Int) Int:
    let _ = output.write(data: "callable\n")
    return combine

fn early(var output: WriteStream) Int:
    let _outer = Resource(label: "outer", output: stdout())
    let _inner = Resource(label: "inner", output: stdout())
    return report(output: var output, label: "return value", value: 5)

fn failure() Result[Int, TextError]:
    return error(TextError("expected"))

fn propagate(output: WriteStream) Result[Int, TextError]:
    let _resource = Resource(label: "propagation", output: output)
    let number = try failure()
    return ok(number)

fn iterable(var output: WriteStream) List[Int]:
    let _ = output.write(data: "iterable\n")
    return [1, 2]

fn exercise() Result[Int, Error]:
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

    var _resource = Resource(label: "normal", output: stdout())
    let completed = unit
    try _resource.close()

    let _ = stdout().write(data: "after normal\n")
    var count = 0

    while count < 2:
        let _resource = Resource(label: "iteration", output: stdout())
        count = count + 1
        continue

    var iterable_out = stdout()

    for value in iterable(output: var iterable_out):
        let _resource = Resource(label: "break", output: stdout())
        break

    match propagate(output: stdout()):
        ok(_):
            try fail(message: "Unexpected case")
        error(_):
            let completed = unit

    var early_out = stdout()
    early(output: var early_out) | try expect_equal(5)

    let _ = stdout().write(data: "finished\n")
    return ok(0)

export fn main() Int:
    match exercise():
        ok(status): return status
        error(cause):
            let written = stderr().write("{cause.message()}\n")
            return 1
