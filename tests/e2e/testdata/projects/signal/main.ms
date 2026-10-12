import panic from "@std/faults.ms"

import Process from "@std/cli.ms"
import WriteStream from "@std/io.ms"
import Closeable from "@std/cleanup.ms"
import parallel from "@std/tasks.ms"

type Resource:
    label: String
    output: WriteStream

impl Closeable for Resource:
    fn close() -> Unit:
        self.output.write(data: "close {self.label}\n".to_bytes())

export fn main(process: Process) -> Int:
    let output = process.stdout
    let child = fn() -> Unit:
        with resource = Resource(label: "child", output: output):
            output.write(data: "ready\n".to_bytes())
            while true:
                continue
    with resource = Resource(label: "parent", output: output):
        let outcome = parallel(tasks: [child])
        return 0
