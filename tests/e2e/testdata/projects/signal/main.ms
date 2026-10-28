from "@std/io.ms" import stdout
from "@std/io.ms" import WriteStream
from "@std/core.ms" import Closeable

type Resource:
    label: String
    output: WriteStream

impl Closeable for Resource:
    var def close() -> Unit:
        let _ignored = self.output.write(f"close {self.label}\n")

export def main() -> Int:
    var output = stdout()
    var _resource = Resource("parent", stdout())
    let _child = Resource("child", stdout())
    let _ignored = output.write("ready\n")
    while True:
        continue
    _resource.close()
    return 0
