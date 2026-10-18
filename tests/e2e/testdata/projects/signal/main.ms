import stdout from "@std/io.ms"
import WriteStream from "@std/io.ms"
import Closeable from "@std/cleanup.ms"
import TaskGroup from "@std/tasks.ms"

type Resource:
    label: String
    output: WriteStream

impl Closeable for Resource:
    fn close() -> Unit:
        self.output.write(data: "close {self.label}\n".to_bytes())

export fn main() -> Int:
    let output = stdout()
    let child = fn():
        with resource = Resource(label: "child", output: output):
            output.write(data: "ready\n".to_bytes())
            while true:
                continue

    with resource = Resource(label: "parent", output: output):
        with group = TaskGroup():
            group.start(child)
            group.join()
            return 0
