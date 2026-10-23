import stdout from "@std/io.ms"
import WriteStream from "@std/io.ms"
import Closeable from "@std/core.ms"

type Resource:
    label: String
    output: WriteStream

impl Closeable for Resource:
    var fn close() Unit:
        let _ignored = self.output.write("close {self.label}\n")

export fn main() Int:
    let output = stdout()

    with resource = Resource("parent", output.clone()):
        with child = Resource("child", output.clone()):
            let _ignored = output.write("ready\n")
            while true:
                continue

    return 0
