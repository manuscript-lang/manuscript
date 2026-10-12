import panic from "@std/faults.ms"

import Process from "@std/cli.ms"
import WriteStream from "@std/io.ms"
import Closeable from "@std/cleanup.ms"
import Result from "@std/result.ms"
import List from "@std/collections.ms"

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
    return error(cause: "expected")

fn propagate(output: WriteStream) -> Result[Int, String]:
    with resource = Resource(label: "propagation", output: output):
        let number = try failure()
        return ok(value: number)

fn iterable(output: WriteStream) -> List[Int]:
    output.write(data: "iterable\n".to_bytes())
    return [1, 2]

export fn main(process: Process) -> Int:
    let total = select(output: process.stdout)(
        second: report(output: process.stdout, label: "second", value: 2),
        first: report(output: process.stdout, label: "first", value: 1),
    )
    if not (total == 3):
        return panic(message: "check failed")
    let pair = Pair(
        second: report(output: process.stdout, label: "pair second", value: 2),
        first: report(output: process.stdout, label: "pair first", value: 1),
    )
    if not (pair.first + pair.second == 3):
        return panic(message: "check failed")
    with resource = Resource(label: "normal", output: process.stdout):
        let completed = unit
    process.stdout.write(data: "after normal\n".to_bytes())
    var count = 0
    while count < 2:
        with resource = Resource(label: "iteration", output: process.stdout):
            count = count + 1
            continue
    for value in iterable(output: process.stdout):
        with resource = Resource(label: "break", output: process.stdout):
            break
    match propagate(output: process.stdout):
        ok(_):
            return panic(message: "Unexpected case")
        error(_):
            let completed = unit
    if not (early(output: process.stdout) == 5):
        return panic(message: "check failed")
    process.stdout.write(data: "finished\n".to_bytes())
    return 0
