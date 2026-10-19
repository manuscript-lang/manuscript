import stdout from "@std/io.ms"
import WriteStream from "@std/io.ms"
import Closeable from "@std/cleanup.ms"

type Resource:
    label: String
    output: WriteStream

impl Closeable for Resource:
    fn close() Unit:
        let _ignored = self.output.write("close {self.label}\n")

export fn main() Int:
    let output = stdout()

    with resource = Resource("parent", output):
        with child = Resource("child", output):
            let _ignored = output.write("ready\n")
            while true:
                continue

    return 0
