import stdout from "@std/io.ms"
import panic from "@std/faults.ms"
import WriteStream from "@std/io.ms"
import Closeable from "@std/cleanup.ms"

type Resource:
    label: String
    output: WriteStream

fn emit(output: WriteStream, text: String) Unit:
    let _ignored = output.write(data: text.to_bytes())

impl Closeable for Resource:
    fn close() Unit:
        emit(self.output, "close {self.label}\n")

type Pair:
    first: Int
    second: Int

fn report(output: WriteStream, label: String, value: Int) Int:
    emit(output, "{label}\n")
    return value

fn combine(first: Int, second: Int) Int:
    return first + second

fn select(output: WriteStream) fn(first: Int, second: Int) Int:
    emit(output, "callable\n")
    return combine

fn early(output: WriteStream) Int:
    with outer = Resource(label: "outer", output):
        with inner = Resource(label: "inner", output):
            return report(output, label: "return value", value: 5)

fn failure() Result[Int, String]:
    return error("expected")

fn propagate(output: WriteStream) Result[Int, String]:
    with resource = Resource(label: "propagation", output):
        let number = try failure()
        return ok(number)

fn iterable(output: WriteStream) List[Int]:
    emit(output, "iterable\n")
    return [1, 2]

export fn main() Int:
    let total = select(output: stdout())(
        second: report(output: stdout(), label: "second", value: 2),
        first: report(output: stdout(), label: "first", value: 1)
    )
    if not (total == 3):
        return panic(message: "check failed")

    let pair = Pair(
        second: report(output: stdout(), label: "pair second", value: 2),
        first: report(output: stdout(), label: "pair first", value: 1)
    )
    if not (pair.first + pair.second == 3):
        return panic(message: "check failed")

    var count = 0
    with resource = Resource(label: "normal", output: stdout()):
        count += 1
    if count != 1:
        return panic(message: "check failed")

    emit(stdout(), "after normal\n")
    count = 0

    while count < 2:
        with resource = Resource(label: "iteration", output: stdout()):
            count += 1
            continue

    for value in iterable(output: stdout()):
        with resource = Resource(label: "break", output: stdout()):
            break
    if propagate(output: stdout()).is_ok():
        return panic(message: "Unexpected case")
    if not (early(output: stdout()) == 5):
        return panic(message: "check failed")
    if stdout().write(data: "finished\n".to_bytes()).is_error():
        return 1

    return 0
