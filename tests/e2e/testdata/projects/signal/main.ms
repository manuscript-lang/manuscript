import stdout from "@std/io.ms"
import WriteStream from "@std/io.ms"
import Closeable from "@std/cleanup.ms"
import TaskGroup from "@std/tasks.ms"

type Resource:
    label: String
    output: WriteStream

impl Closeable for Resource:
    fn close() Unit:
        let _ignored = self.output.write("close {self.label}\n".to_bytes())

export fn main() Int:
    let output = stdout()
    let child = fn():
        with resource = Resource("child", output):
            let _ignored = output.write("ready\n".to_bytes())
            while true:
                continue

    with resource = Resource("parent", output):
        with group = TaskGroup():
            let _ignored = group.start(child)
            let _joined = group.join()
            return 0
