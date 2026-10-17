import stdout from "@std/io.ms"
import panic from "@std/faults.ms"
import WriteStream from "@std/io.ms"
import Closeable from "@std/cleanup.ms"

type Resource:
    label: String
    output: WriteStream

impl Closeable for Resource:
    fn close() -> Unit:
        self.output.write(data: "close {self.label}\n".to_bytes())

type Pair:
    first: Int
    second: Int

fn report(output: WriteStream, label: String, value: Int) -> Int:
    output.write(data: "{label}\n".to_bytes())
    return value

fn combine(first: Int, second: Int) -> Int:
    return first + second

fn select(output: WriteStream) -> fn(first: Int, second: Int) -> Int:
    output.write(data: "callable\n".to_bytes())
    return combine

fn early(output: WriteStream) -> Int:
    with outer = Resource(label: "outer", output: output):
        with inner = Resource(label: "inner", output: output):
            return report(output: output, label: "return value", value: 5)

fn failure() -> Result[Int, String]:
    return error("expected")

fn propagate(output: WriteStream) -> Result[Int, String]:
    with resource = Resource(label: "propagation", output: output):
        let number = try failure()
        return ok(number)

fn iterable(output: WriteStream) -> List[Int]:
    output.write(data: "iterable\n".to_bytes())
    return [1, 2]

export fn main() -> Int:
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

    with resource = Resource(label: "normal", output: stdout()):
        let completed = unit
    stdout().write(data: "after normal\n".to_bytes())
    var count = 0

    while count < 2:
        with resource = Resource(label: "iteration", output: stdout()):
            count = count + 1
            continue

    for value in iterable(output: stdout()):
        with resource = Resource(label: "break", output: stdout()):
            break
    if propagate(output: stdout()).is_ok():
        return panic(message: "Unexpected case")
    if not (early(output: stdout()) == 5):
        return panic(message: "check failed")

    stdout().write(data: "finished\n".to_bytes())
    return 0
