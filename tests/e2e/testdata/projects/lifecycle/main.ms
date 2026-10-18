import stdout from "@std/io.ms"
import panic from "@std/faults.ms"
import WriteStream from "@std/io.ms"
import Closeable from "@std/cleanup.ms"

type Resource:
    label: String
    output: WriteStream

fn emit(output: WriteStream, text: String) Unit:
    let _ignored = output.write(text.to_bytes())

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
    with outer = Resource("outer", output):
        with inner = Resource("inner", output):
            return report(output, "return value", 5)

fn failure() Result[Int, String]:
    return error("expected")

fn propagate(output: WriteStream) Result[Int, String]:
    with resource = Resource("propagation", output):
        let number = try failure()
        return ok(number)

fn iterable(output: WriteStream) List[Int]:
    emit(output, "iterable\n")
    return [1, 2]

export fn main() Int:
    let total = select(stdout())(
        second: report(stdout(), "second", 2),
        first: report(stdout(), "first", 1)
    )
    if not (total == 3):
        return panic("check failed")

    let pair = Pair(
        second: report(stdout(), "pair second", 2),
        first: report(stdout(), "pair first", 1)
    )
    if not (pair.first + pair.second == 3):
        return panic("check failed")

    var count = 0
    with resource = Resource("normal", stdout()):
        count += 1
    if count != 1:
        return panic("check failed")

    emit(stdout(), "after normal\n")
    count = 0

    while count < 2:
        with resource = Resource("iteration", stdout()):
            count += 1
            continue

    for value in iterable(stdout()):
        with resource = Resource("break", stdout()):
            break
    if propagate(stdout()).is_ok():
        return panic("Unexpected case")
    if not (early(stdout()) == 5):
        return panic("check failed")
    if stdout().write("finished\n".to_bytes()).is_error():
        return 1

    return 0
