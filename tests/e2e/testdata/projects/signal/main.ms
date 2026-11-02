import stdout from "@std/io/io.ms"
import WriteStream from "@std/io/io.ms"
import Closeable from "@std/core.ms"

type Resource:
    label: String
    output: WriteStream

impl Closeable for Resource:
    var fn close() Unit!:
        let _ignored = self.output.write("close {self.label}\n")
        return ok(unit)

export fn main() Int:
    var output = stdout()
    var _resource = Resource("parent", stdout())
    let _child = Resource("child", stdout())
    let _ignored = output.write("ready\n")
    while true:
        continue
    _resource.close().get(none)
    return 0
